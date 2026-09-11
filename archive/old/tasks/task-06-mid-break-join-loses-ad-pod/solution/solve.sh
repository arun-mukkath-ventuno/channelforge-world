#!/usr/bin/env bash
# Oracle — reference fix, used only to validate the task is solvable. Never shown to the agent.
#
# Root cause: detectAvails only produces an Avail when both a break's opening tag (CUE-OUT/
# DATERANGE-OUT) and closing tag (CUE-IN/DATERANGE-IN) are present in the manifest it's given.
# ChannelForge's origin serves a fixed-size sliding window of recent segments, so a break's opening
# tag always ages out of that window before its closing tag does (by a span equal to the break's
# own duration). During that span, a session whose first request for the break lands then gets
# nothing: no Avail means no opportunityId, so the manifest hot path has nothing to look up a
# cached decision under or hand to the decider — it silently falls through to raw, unstitched
# origin content, even for a session that had already been decided a pod for this exact break
# moments earlier and simply reconnected.
#
# Fix, two files:
#  1. packages/data-plane/src/avails.ts — recognize this "headless" case (a CUE-IN, and its
#     accompanying DATERANGE-IN, with nothing open) as a distinct Avail shape carrying the
#     producer's externalBreakId but no sequence-derived id (none is computable without the
#     CUE-OUT) — falling back to a stable, break-id-derived opportunityId instead. Scoped tightly
#     to the very start of a manifest (frozen the moment any real avail opens or closes), so it
#     can't misfire on ordinary avails elsewhere in the same window.
#  2. packages/data-plane/src/server.ts — when a decision is first made for any avail carrying an
#     externalBreakId, also cache it under that break-id-derived key (reusing the existing
#     PodCache interface as-is); when the primary sequence-derived cache lookup misses for an
#     avail with an externalBreakId, retry under the break-id key before asking the decider again.
#     This is what lets a session's earlier decision reattach to the headless tail instead of
#     either silently degrading to origin or getting a fresh, different re-decision.
set -euo pipefail
cd /app

patch -p1 <<'PATCH'
--- a/packages/data-plane/src/avails.ts
+++ b/packages/data-plane/src/avails.ts
@@ -29,18 +29,34 @@
   startLine: number;
   /** Line index of the CUE-IN marker. */
   endLine: number;
+  /** True when this avail's own CUE-OUT/DATERANGE-OUT had already aged out of the origin's live
+   *  window before its CUE-IN did — i.e. this window "joined mid-break" (PRD §41 extension). Only
+   *  possible as the very first avail-shaped region in a manifest. `opportunityId` falls back to a
+   *  stable externalBreakId-derived id (no sequence-derived id is computable without the CUE-OUT),
+   *  and `duration`/`measuredDuration` cover only the portion still visible in this window. */
+  headless?: boolean;
 }

 const MEDIA_SEQUENCE = /^#EXT-X-MEDIA-SEQUENCE:(\d+)/;
 const EXTINF = /^#EXTINF:([\d.]+)/;
 const PROGRAM_DATE_TIME = /^#EXT-X-PROGRAM-DATE-TIME:(.+)/;

+/** The stable, producer-break-id-derived opportunityId used for a `headless` avail (see
+ *  `Avail.headless`) — and, from the data plane's cache, as a secondary lookup key so a session
+ *  already decided a pod for this break while its CUE-OUT was still visible can still find it
+ *  once only the headless tail remains. */
+export function breakOpportunityId(externalBreakId: string): string {
+  return `opp_break_${externalBreakId}`;
+}
+
 /** Detect all complete avails in the manifest. Incomplete trailing avails (a
  *  CUE-OUT with no CUE-IN yet in the window) are ignored — PRD §41. */
 export function detectAvails(manifest: string, channelId: string): Avail[] {
   const lines = manifest.split("\n");

   let mediaSequence = 0;
+  let windowStartSequence = 0;
+  let sawMediaSequenceTag = false;
   let lastPdt: string | undefined;
   // The DATERANGE ID seen in the current segment's tag block, cleared at each segment boundary so
   // one break's id never leaks onto the next. ChannelForge emits the CUE-OUT and its DATERANGE-OUT
@@ -48,6 +64,20 @@
   let blockBreakId: string | undefined;
   const avails: Avail[] = [];

+  // Only relevant before the first avail is opened or produced (PRD §41 extension): tracks
+  // whether we might still be inside a break that started before this window (a "headless" avail
+  // — see Avail.headless), the most recent DATERANGE id seen while in that state, the line index
+  // where real content (as opposed to playlist header tags) begins, and the duration accumulated
+  // since then. All frozen once a real CUE-OUT opens or any avail is produced.
+  let atWindowStart = true;
+  let pendingBreakId: string | undefined;
+  let firstContentLine: number | null = null;
+  let sinceStartDuration = 0;
+  // Set to the CUE-IN's line index once we've seen a headless CUE-IN but no id yet — real
+  // producers emit CUE-IN before its DATERANGE-IN (the reverse of the CUE-OUT/DATERANGE-OUT
+  // order), so the id, if any, is still to come in the same tag block.
+  let awaitingHeadlessCloseLine: number | null = null;
+
   // Pending avail state while we walk from CUE-OUT to CUE-IN.
   let open: {
     startLine: number;
@@ -65,6 +95,10 @@
     const seqMatch = trimmed.match(MEDIA_SEQUENCE);
     if (seqMatch) {
       mediaSequence = Number(seqMatch[1]);
+      if (!sawMediaSequenceTag) {
+        windowStartSequence = mediaSequence;
+        sawMediaSequenceTag = true;
+      }
       continue;
     }

@@ -75,13 +109,35 @@
     }

     const marker = parseMarkerLine(line, i);
+    if (atWindowStart && firstContentLine === null) {
+      const isContentLine = marker !== null || EXTINF.test(trimmed) || (trimmed.length > 0 && !trimmed.startsWith("#"));
+      if (isContentLine) firstContentLine = i;
+    }
+
     if (marker?.kind === "daterange" && marker.id) {
       blockBreakId = marker.id;
+      if (atWindowStart && !open) pendingBreakId = marker.id;
       // DATERANGE-OUT typically follows the CUE-OUT in the same block; attach it to the open avail.
       if (open && open.externalBreakId === undefined) open.externalBreakId = marker.id;
+      if (awaitingHeadlessCloseLine !== null && firstContentLine !== null) {
+        // The trailing DATERANGE-IN for a headless CUE-IN seen just above has arrived.
+        avails.push({
+          opportunityId: breakOpportunityId(marker.id),
+          channelId,
+          externalBreakId: marker.id,
+          duration: sinceStartDuration,
+          measuredDuration: sinceStartDuration,
+          startSequence: windowStartSequence,
+          startLine: firstContentLine,
+          endLine: awaitingHeadlessCloseLine,
+          headless: true,
+        });
+        awaitingHeadlessCloseLine = null;
+      }
       continue;
     }
     if (marker?.kind === "cue_out" && !open) {
+      atWindowStart = false; // a real CUE-OUT means we're not inside a headless tail
       open = {
         startLine: i,
         startSequence: mediaSequence,
@@ -93,21 +149,48 @@
       };
       continue;
     }
-    if (marker?.kind === "cue_in" && open) {
-      const declared = open.declaredDuration;
-      avails.push({
-        opportunityId: `opp_${channelId}_${open.startSequence}`,
-        channelId,
-        ...(open.externalBreakId === undefined ? {} : { externalBreakId: open.externalBreakId }),
-        duration: declared ?? open.measuredDuration,
-        ...(declared === undefined ? {} : { declaredDuration: declared }),
-        measuredDuration: open.measuredDuration,
-        startSequence: open.startSequence,
-        ...(open.pdt === undefined ? {} : { programDateTime: open.pdt }),
-        startLine: open.startLine,
-        endLine: i,
-      });
-      open = null;
+    if (marker?.kind === "cue_in") {
+      if (open) {
+        const declared = open.declaredDuration;
+        avails.push({
+          opportunityId: `opp_${channelId}_${open.startSequence}`,
+          channelId,
+          ...(open.externalBreakId === undefined ? {} : { externalBreakId: open.externalBreakId }),
+          duration: declared ?? open.measuredDuration,
+          ...(declared === undefined ? {} : { declaredDuration: declared }),
+          measuredDuration: open.measuredDuration,
+          startSequence: open.startSequence,
+          ...(open.pdt === undefined ? {} : { programDateTime: open.pdt }),
+          startLine: open.startLine,
+          endLine: i,
+        });
+        open = null;
+        atWindowStart = false;
+        continue;
+      }
+      if (atWindowStart && firstContentLine !== null) {
+        // A CUE-IN with no matching CUE-OUT anywhere in this window: the break started before the
+        // origin's live window began (its own CUE-OUT has already scrolled out). Recover it from
+        // the closing DATERANGE-IN's id — real producers emit that DATERANGE-IN just after CUE-IN,
+        // so if a break id was already seen (a producer emitting the reverse order) push now;
+        // otherwise wait for it (see the `daterange` branch above).
+        if (pendingBreakId !== undefined) {
+          avails.push({
+            opportunityId: breakOpportunityId(pendingBreakId),
+            channelId,
+            externalBreakId: pendingBreakId,
+            duration: sinceStartDuration,
+            measuredDuration: sinceStartDuration,
+            startSequence: windowStartSequence,
+            startLine: firstContentLine,
+            endLine: i,
+            headless: true,
+          });
+        } else {
+          awaitingHeadlessCloseLine = i;
+        }
+      }
+      atWindowStart = false;
       continue;
     }

@@ -116,6 +199,7 @@
     if (infMatch) {
       const segDur = Number(infMatch[1]);
       if (open) open.measuredDuration += segDur;
+      if (atWindowStart) sinceStartDuration += segDur;
       // The URI line follows; advance the sequence when we consume it below.
     } else if (trimmed.length > 0 && !trimmed.startsWith("#")) {
       // A media segment URI line — the tag block ended, so a DATERANGE id does not carry over.
PATCH

patch -p1 <<'PATCH'
--- a/packages/data-plane/src/server.ts
+++ b/packages/data-plane/src/server.ts
@@ -13,7 +13,7 @@
 import type { ObjectStore } from "@ssai/storage";
 import { OriginClient } from "./origin.js";
 import { absolutizeManifest } from "./origin-rewrite.js";
-import { detectAvails } from "./avails.js";
+import { detectAvails, breakOpportunityId } from "./avails.js";
 import { resolvePodSegments, type RenderedPodItem } from "./media.js";
 import { stitchManifest } from "./stitch.js";
 import { HttpPodDecider, type PodDecider } from "./decider.js";
@@ -80,11 +80,33 @@
     const rendered = new Map<string, RenderedPodItem[]>();
     for (const avail of avails) {
       let pod: PodItem[] | undefined;
-      const cached = await podCache.get(session, avail.opportunityId);
-      if (cached) pod = cached.pod;
-      else if (decider) {
+      let cached = await podCache.get(session, avail.opportunityId);
+      if (!cached && avail.externalBreakId !== undefined) {
+        // A break whose CUE-OUT/DATERANGE-OUT has aged out of the origin's live window (see
+        // avails.ts's `headless` avails) can't compute the same sequence-derived opportunityId it
+        // had while its opening tag was still visible. Its stable producer break id still can —
+        // retry under that key so a session already decided a pod for this exact break still gets
+        // it reattached, instead of silently falling back to raw origin content for the tail.
+        cached = await podCache.get(session, breakOpportunityId(avail.externalBreakId));
+      }
+      if (cached) {
+        pod = cached.pod;
+      } else if (decider) {
         const decided = await decider.decide({ sessionId: session, channelId: channel, avail });
-        if (decided) pod = decided;
+        if (decided) {
+          pod = decided;
+          if (avail.externalBreakId !== undefined) {
+            // Index this decision by its stable break id too, so it's still reachable once this
+            // break's CUE-OUT ages out of the live window and only a headless tail remains.
+            await podCache.set({
+              sessionId: session,
+              opportunityId: breakOpportunityId(avail.externalBreakId),
+              channelId: channel,
+              breakDuration: avail.duration,
+              pod: decided,
+            });
+          }
+        }
       }
       if (pod) rendered.set(avail.opportunityId, await resolvePodSegments(pod, store, { channelId: channel }));
     }
PATCH

npm run build
restart-ssai
