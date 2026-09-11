#!/usr/bin/env bash
# Verifier. Confirmed real defect (see docs/ecosystem.md): sendAdBeacon's wire payload is only
# `{event, session_id, ad_id}` — it never forwards the one piece of information the player already
# has per airing (the ad window's own START-DATE, threaded through startAdBeaconWatcher's `tick()`
# as `w.start`) that would let the server's existing pod_id-aware dedup key (packages/control-plane
# events-normalize.ts's deriveEventId: `[session_id, pod_id, ad_id, eventType]`) tell two separate
# airings of the same creative apart. Because pod_id is always empty on the wire, a creative that
# airs a second time later in the same session computes the *same* deterministic event_id as its
# first airing, and the server's `ON CONFLICT (event_id) DO NOTHING` silently drops the repeat.
#
# Two black-box cases against the real client watcher (mocked fetch/timers, no live SSAI backend
# needed — this defect and its fix are entirely client-side):
#   1. Two distinct airings of the same creative in one session must produce distinguishable
#      ad_start payloads (forces a real per-occurrence fix, not a no-op).
#   2. Re-running the watcher fresh (simulating a page/manifest reload) against the *same* single
#      airing must reproduce an *identical* payload to before (forces the fix to derive its
#      distinguishing value deterministically from the airing itself — e.g. the window's start
#      time — not from wall-clock "now" or Math.random(), which would just trade one broken
#      behavior for another: real network retries of the same airing would stop deduping too).
#
# Anti-gaming: confirmed live (docker-compose'd this task standalone, planted a "fix" that added a
# distinguishing field named something the real server never reads) that checking only "the two
# payloads differ / match" isn't enough — a fix can satisfy that by adding ANY arbitrarily-named
# field, or by mutating ad_id itself, without actually wiring into the real server's dedup key
# (packages/control-plane/src/events-normalize.ts's deriveEventId, which reads specifically
# `raw.pod_id`) — passing this grader while leaving the real production bug, and the analytics it
# corrupts, completely unfixed. So both tests below: (a) assert ad_id/session_id are byte-identical
# across the two payloads (a correct fix must not "solve" this by changing creative/session
# identity), and (b) recompute the event id via a trusted, verbatim copy of the real server's
# deriveEventId against the captured payloads, and assert on THAT — not just on payload equality —
# so the fix is graded against the actual field the production dedup key reads.
set -euo pipefail

mkdir -p /logs/verifier
cd /app

# Anti-gaming: run with an explicit --config pointing outside /app, so any vitest.config.*
# (+ setupFiles) the agent's own patch may have left in the repo — e.g. one that monkey-patches
# expect.extend()/toEqual so every assertion reports pass:true — is never auto-discovered. This
# config carries no setupFiles of its own. Same guard as task-05/06/07.
cat > /tmp/trusted.vitest.config.mjs <<'CONFIG'
export default { test: {} };
CONFIG

cat > src/lib/ssai-repeat-airing.test.ts <<'TESTFILE'
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createHash } from "node:crypto";
import { startAdBeaconWatcher } from "./ssai.js";

// Trusted, verbatim copy of the real server's dedup-id derivation (vendor/ssaiadserver's
// packages/control-plane/src/events-normalize.ts::deriveEventId) — embedded here so this grader
// validates the fix against the actual field the production dedup key reads (`pod_id`), not just
// "the client's outbound payloads look different somehow". See the note above this heredoc.
function deriveEventId(raw: Record<string, unknown>, eventType: string): string {
  if (raw.event_id) return String(raw.event_id);
  const isAdLifecycle = eventType.startsWith("ad_") && eventType !== "ad_error";
  if (isAdLifecycle && raw.session_id) {
    const basis = [raw.session_id, raw.pod_id ?? "", raw.ad_id ?? "", eventType].join("|");
    return `evt_${createHash("sha1").update(basis).digest("hex").slice(0, 24)}`;
  }
  return `evt_${createHash("sha1").update(`${JSON.stringify(raw)}|no-random-in-tests`).digest("hex").slice(0, 24)}`;
}

function manifestFor(airings: { start: string; durationSec: number; adId: string }[]): string {
  return airings
    .map(
      (a) =>
        `#EXT-X-DATERANGE:CLASS="com.fastworld.ad",START-DATE="${a.start}",DURATION=${a.durationSec},X-AD-ID="${a.adId}"`,
    )
    .join("\n");
}

describe("sendAdBeacon wire payload — repeat airings within one session (PRD §60 task 6)", () => {
  let sentEventBodies: Record<string, unknown>[];
  let playhead: number;

  function stubFetch(manifest: string) {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: unknown, init?: { body?: string }) => {
        const u = String(url);
        if (u.includes("/v1/events")) {
          // sendAdBeacon's fallback path when navigator.sendBeacon is unavailable (default in
          // vitest's node environment) — capture what actually goes on the wire.
          if (init?.body) sentEventBodies.push(JSON.parse(init.body));
          return { ok: true, text: async () => "" };
        }
        return { ok: true, text: async () => manifest };
      }),
    );
  }

  beforeEach(() => {
    sentEventBodies = [];
    playhead = 0;
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.useRealTimers();
  });

  it("sends distinguishable ad_start payloads for two separate airings of the same creative", async () => {
    stubFetch(
      manifestFor([
        { start: "2026-09-07T00:00:00.000Z", durationSec: 4, adId: "cr_repeat" },
        { start: "2026-09-07T00:05:00.000Z", durationSec: 4, adId: "cr_repeat" },
      ]),
    );

    const stop = startAdBeaconWatcher({
      sessionId: "sess_1",
      manifestUrl: "http://origin/manifest.m3u8",
      playheadDate: () => playhead,
      refetchMs: 1_000_000,
      tickMs: 10,
    });
    await vi.advanceTimersByTimeAsync(0); // let the initial refresh() resolve

    playhead = Date.parse("2026-09-07T00:00:00.500Z"); // inside first airing
    await vi.advanceTimersByTimeAsync(20);

    playhead = Date.parse("2026-09-07T00:05:00.500Z"); // inside second airing
    await vi.advanceTimersByTimeAsync(20);

    stop();

    const starts = sentEventBodies.filter((b) => b.event === "ad_start");
    expect(starts).toHaveLength(2);
    expect(starts[0]).not.toEqual(starts[1]);

    // The fix must not "solve" this by mutating creative/session identity — only a per-occurrence
    // distinguishing value may vary.
    expect(starts[1]!.ad_id).toBe(starts[0]!.ad_id);
    expect(starts[1]!.session_id).toBe(starts[0]!.session_id);

    // Graded against the real server's actual dedup key, not just "payloads differ somehow" — a
    // fix that adds any arbitrarily-named field (which the real server would silently ignore)
    // computes the SAME real event id for both airings and fails this.
    const id1 = deriveEventId(starts[0]!, "ad_start");
    const id2 = deriveEventId(starts[1]!, "ad_start");
    expect(id1).not.toBe(id2);
  });

  it("reproduces an identical payload for the same single airing across a fresh watcher (page reload)", async () => {
    const oneAiring = manifestFor([
      { start: "2026-09-07T00:00:00.000Z", durationSec: 4, adId: "cr_repeat" },
    ]);

    async function runOnce(): Promise<Record<string, unknown>> {
      sentEventBodies = [];
      playhead = 0;
      stubFetch(oneAiring);
      const stop = startAdBeaconWatcher({
        sessionId: "sess_1",
        manifestUrl: "http://origin/manifest.m3u8",
        playheadDate: () => playhead,
        refetchMs: 1_000_000,
        tickMs: 10,
      });
      await vi.advanceTimersByTimeAsync(0);
      playhead = Date.parse("2026-09-07T00:00:00.500Z");
      await vi.advanceTimersByTimeAsync(20);
      stop();
      const starts = sentEventBodies.filter((b) => b.event === "ad_start");
      expect(starts).toHaveLength(1);
      return starts[0]!;
    }

    const first = await runOnce();
    const second = await runOnce();
    expect(first).toEqual(second);

    // Same real-dedup-key check as above, in the "must still collapse" direction: a fix that
    // derives its distinguishing value from wall-clock now()/Math.random() rather than the
    // airing's own window start would compute a DIFFERENT real event id here and fail this,
    // even though it might pass a naive payload-equality-only check.
    const id1 = deriveEventId(first, "ad_start");
    const id2 = deriveEventId(second, "ad_start");
    expect(id1).toBe(id2);
  });
});
TESTFILE

if npx vitest run --config /tmp/trusted.vitest.config.mjs src/lib/ssai-repeat-airing.test.ts src/lib/ssai.test.ts > /logs/verifier/vitest.log 2>&1; then
  success=1.0
  success_int=1
else
  success=0.0
  success_int=0
fi

# NOTE: correct_diagnosis/policy_compliance/side_effect_safety are placeholders (fixed at 1.0),
# same as task-01/02/05/06/07/08 — no automated side-effect-safety check exists yet in this world.
cat > /logs/verifier/reward.json <<JSON
{
  "task_success": $success,
  "correct_diagnosis": $success,
  "policy_compliance": 1.0,
  "side_effect_safety": 1.0
}
JSON

echo "$success_int" > /logs/verifier/reward.txt
echo "verifier: task_success=$success (see vitest.log)"
