#!/usr/bin/env bash
# Oracle — reference fix, used only to validate the task is solvable. Never shown to the agent.
#
# Root cause: sendAdBeacon's wire payload is only `{event, session_id, ad_id}`. The server's
# dedup key (events-normalize.ts's deriveEventId) already supports a pod_id field specifically so
# repeat airings of the same creative in one session get distinct event ids — but the client never
# sends it, even though startAdBeaconWatcher's tick() already has exactly the right per-airing
# value on hand: the ad window's own `start` (parsed from the manifest's DATERANGE START-DATE,
# fresh for every real airing). Threading that through as pod_id is the minimal fix: it's
# deterministic per airing (so a genuine re-send of the same airing after a manifest refresh still
# produces the same id and correctly collapses), while two different airings of the same creative
# get different ids and are both recorded.
#
# Exact string replacement (not `patch -p1`) — same reasoning as task-07's oracle: whitespace-
# sensitive hand-crafted unified diffs are brittle here, and node (unlike python3) is guaranteed
# present in this image.
set -euo pipefail
cd /app

node -e '
const fs = require("fs");
const path = "src/lib/ssai.ts";
const src = fs.readFileSync(path, "utf8");

const oldSig = [
  "export function sendAdBeacon(sessionId: string, event: AdBeacon, adId: string): void {",
  "  const body = JSON.stringify({ event, session_id: sessionId, ad_id: adId });",
].join("\n");
const newSig = [
  "export function sendAdBeacon(sessionId: string, event: AdBeacon, adId: string, occurrenceStart: number): void {",
  "  const body = JSON.stringify({ event, session_id: sessionId, ad_id: adId, pod_id: String(occurrenceStart) });",
].join("\n");
if (!src.includes(oldSig)) throw new Error("expected sendAdBeacon block not found — ssai.ts must have changed upstream");

const oldCall = "sendAdBeacon(opts.sessionId, beacon, w.adId);";
const newCall = "sendAdBeacon(opts.sessionId, beacon, w.adId, w.start);";
if (!src.includes(oldCall)) throw new Error("expected sendAdBeacon call site not found — ssai.ts must have changed upstream");

const fixed = src.replace(oldSig, newSig).replace(oldCall, newCall);
fs.writeFileSync(path, fixed);
'

restart-fast-web
