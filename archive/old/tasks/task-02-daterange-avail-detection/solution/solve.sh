#!/usr/bin/env bash
# Oracle — reference fix, used only to validate the task is solvable. Never shown to the agent.
#
# Unlike task-01, there is no regression.patch baked into the image to reverse: the defect
# (avails.ts never recognizing DATERANGE cues) is already present in pristine vendored
# ssaiadserver source, not something injected for this task. So the Oracle applies a real forward
# fix instead of a reversal. The patch is inlined here (rather than a separate solution/ file
# copied at build time) because — unlike setup/regression.patch — nothing in this task's
# environment/Dockerfile bakes a solution artifact into the image; only solve.sh itself is handed
# to the Oracle's turn.
set -euo pipefail
cd /app

patch -p1 <<'PATCH'
--- a/packages/data-plane/src/avails.ts
+++ b/packages/data-plane/src/avails.ts
@@ -65,17 +65,24 @@
     }

     const marker = parseMarkerLine(line, i);
-    if (marker?.kind === "cue_out" && !open) {
+    // A DATERANGE cue-out carries a duration (PLANNED-DURATION/DURATION); a DATERANGE cue-in
+    // does not (only SCTE35-IN) — that presence/absence is what distinguishes open vs close,
+    // exactly mirroring cue_out/cue_in. This is ChannelForge's only real signalling format
+    // (worker/scte35.py daterange_out/daterange_in) — without this, no avail is ever detected
+    // on a real ChannelForge channel.
+    const isDaterangeOut = marker?.kind === "daterange" && marker.duration !== undefined;
+    const isDaterangeIn = marker?.kind === "daterange" && marker.duration === undefined;
+    if ((marker?.kind === "cue_out" || isDaterangeOut) && !open) {
       open = {
         startLine: i,
         startSequence: mediaSequence,
         measuredDuration: 0,
-        ...(marker.duration === undefined ? {} : { declaredDuration: marker.duration }),
+        ...(marker!.duration === undefined ? {} : { declaredDuration: marker!.duration }),
         ...(lastPdt === undefined ? {} : { pdt: lastPdt }),
       };
       continue;
     }
-    if (marker?.kind === "cue_in" && open) {
+    if ((marker?.kind === "cue_in" || isDaterangeIn) && open) {
       const declared = open.declaredDuration;
       avails.push({
         opportunityId: `opp_${channelId}_${open.startSequence}`,
PATCH

npm run build
restart-ssai
