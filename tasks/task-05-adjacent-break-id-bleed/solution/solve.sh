#!/usr/bin/env bash
# Oracle — reference fix, used only to validate the task is solvable. Never shown to the agent.
#
# Root cause: detectAvails treats any DATERANGE marker's id as a candidate for the currently-open
# avail, filling externalBreakId only when it's still undefined. A DATERANGE-IN (closes a break)
# and a DATERANGE-OUT (opens one) are otherwise indistinguishable to the parser, and duration isn't
# a reliable signal (a real SCTE35-OUT can omit DURATION/PLANNED-DURATION — see the pristine "does
# not leak one break's id onto a later break that has none" test). So when two breaks are
# back-to-back in the same segment tag block, the first break's closing DATERANGE-IN id gets
# remembered and then wrongly attached to the second break's freshly-opened avail, because the
# "only fill if undefined" guard never lets the second break's own DATERANGE-OUT correct it.
#
# Fix, two files: (1) the marker parser gains a real, unambiguous out/in signal (presence of
# SCTE35-OUT vs SCTE35-IN, which ChannelForge's worker/scte35.py always emits for daterange_out/
# daterange_in respectively); (2) detectAvails only lets a DATERANGE-OUT set the current block's
# id / the open avail's externalBreakId, and always trusts the latest one rather than only filling
# an undefined slot.
set -euo pipefail
cd /app

patch -p1 <<'PATCH'
--- a/packages/core/src/scte.ts
+++ b/packages/core/src/scte.ts
@@ -21,6 +21,10 @@ export interface ParsedMarker {
   /** DATERANGE ID attribute, when present. ChannelForge threads its stable break_id here
    *  (`#EXT-X-DATERANGE:ID="BRK-…"`), so downstream reconciliation can key on it. */
   id?: string;
+  /** For a `daterange` marker: whether it carries `SCTE35-OUT` (opens a break, `true`) or
+   *  `SCTE35-IN` (closes one, `false`). Undefined if the line has neither attribute. Duration is
+   *  NOT a reliable out/in signal - a real SCTE35-OUT can omit DURATION/PLANNED-DURATION. */
+  scte35Out?: boolean;
   /** True when a duration was expected but could not be parsed (PRD §41). */
   invalidDuration?: boolean;
 }
@@ -51,11 +55,14 @@ export function parseMarkerLine(line: string, lineIndex: number): ParsedMarker
     const attrs = trimmed.slice("#EXT-X-DATERANGE".length).replace(/^:/, "");
     const duration = parseAttr(attrs, "DURATION") ?? parseAttr(attrs, "PLANNED-DURATION");
     const id = parseStringAttr(attrs, "ID");
+    const hasOut = /(^|,)\s*SCTE35-OUT\s*=/i.test(attrs);
+    const hasIn = /(^|,)\s*SCTE35-IN\s*=/i.test(attrs);
     return {
       kind: "daterange",
       lineIndex,
       raw: trimmed,
       ...(duration === null ? {} : { duration }),
       ...(id === null ? {} : { id }),
+      ...(hasOut === hasIn ? {} : { scte35Out: hasOut }),
     };
   }

PATCH

patch -p1 <<'PATCH'
--- a/packages/data-plane/src/avails.ts
+++ b/packages/data-plane/src/avails.ts
@@ -76,9 +76,16 @@ export function detectAvails(manifest: string, channelId: string): Avail[] {

     const marker = parseMarkerLine(line, i);
     if (marker?.kind === "daterange" && marker.id) {
-      blockBreakId = marker.id;
-      // DATERANGE-OUT typically follows the CUE-OUT in the same block; attach it to the open avail.
-      if (open && open.externalBreakId === undefined) open.externalBreakId = marker.id;
+      // Only a DATERANGE-OUT (SCTE35-OUT) identifies an avail's producer break id. A DATERANGE-IN
+      // (SCTE35-IN) closes whatever avail is already open - using duration to tell them apart is
+      // NOT reliable (a real SCTE35-OUT can omit DURATION/PLANNED-DURATION), and treating a closing
+      // DATERANGE-IN as an id source lets it leak forward onto the next avail opened in the same
+      // tag block (two breaks scheduled back-to-back with no gap between them).
+      if (marker.scte35Out === true) {
+        blockBreakId = marker.id;
+        // DATERANGE-OUT typically follows the CUE-OUT in the same block; attach it to the open avail.
+        if (open) open.externalBreakId = marker.id;
+      }
       continue;
     }
     if (marker?.kind === "cue_out" && !open) {
PATCH

npm run build
restart-ssai
