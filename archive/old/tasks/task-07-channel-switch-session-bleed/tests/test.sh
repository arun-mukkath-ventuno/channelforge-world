#!/usr/bin/env bash
# Verifier. Confirmed real defect (see docs/ecosystem.md): packages/persistence/src/repositories/
# sessions.ts's ensureSession upserts a playback_sessions row with `ON CONFLICT (id) DO NOTHING`.
# ensureSession is called on every /v1/ad-decision request with that request's own channel_id
# (control-plane/src/server.ts), and /v1/ad-decision explicitly supports a caller-supplied
# session_id (a real, already-documented path for a client that keeps one session id across a
# multi-channel viewing session). So the first channel a session id is ever ensured under is
# permanent — a later ad-decision for the same session under a different channel is correctly
# recorded (opportunities/decisions/events all carry that request's own channel_id directly), but
# the session's own row, and anything trusting sessions.channel_id, stays stuck on the original
# channel forever.
#
# Two new test files (neither exists in pristine ssaiadserver — this behavior was never covered
# before this task, same discipline as task-05/06):
#   - session-channel-rebind.test.ts (persistence): unit-level, directly against ensureSession/
#     getSession, mirroring repositories.test.ts's own freshDb() pg-mem harness.
#   - session-channel-rebind.test.ts (control-plane): integration-level, two /v1/ad-decision calls
#     for the same session_id under two different channels, then GET /v1/sessions/:id — mirroring
#     server.test.ts's own build() pg-mem harness (same one the pristine reconciliation test at
#     "records external_break_id from an ad-decision" already uses for /v1/ad-decision).
# Both packages' real, pristine, unmodified test files (repositories.test.ts, server.test.ts) run
# alongside as the regression-safety plane — they already cover ensureSession/the ad-decision
# endpoint for the ordinary single-channel-per-session case, so a fix that breaks that would fail
# them, not just this task's own new files.
set -euo pipefail

mkdir -p /logs/verifier
cd /app

# Anti-gaming (carried forward from task-05/06, confirmed there to be a real, exploitable hole):
# run with an explicit --config pointing outside /app, so any vitest.config.* (+ setupFiles) the
# agent's own patch may have left in the repo is never auto-discovered.
cat > /tmp/trusted.vitest.config.mjs <<'CONFIG'
export default { test: {} };
CONFIG

cat > packages/persistence/src/session-channel-rebind.test.ts <<'TESTFILE'
import { describe, it, expect, beforeEach } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";
import { newDb } from "pg-mem";
import type { Queryable } from "./db.js";
import { ensureSession, getSession } from "./repositories/sessions.js";
import { insertChannel } from "./repositories/channels.js";

const here = dirname(fileURLToPath(import.meta.url));
const MIG_DIR = resolve(here, "../../../migrations");
const SCHEMA = readdirSync(MIG_DIR)
  .filter((f) => f.endsWith(".sql"))
  .sort()
  .map((f) => readFileSync(join(MIG_DIR, f), "utf8"))
  .join("\n");

function freshDb(): Queryable {
  const mem = newDb();
  mem.public.none(SCHEMA);
  const { Pool } = mem.adapters.createPg();
  return new Pool() as unknown as Queryable;
}

let db: Queryable;
beforeEach(async () => {
  db = freshDb();
  // playback_sessions.channel_id is FK-constrained to channels(id) — seed the channels this
  // suite switches between before any ensureSession call references them.
  await insertChannel(db, { id: "channel_food", name: "Food", originUrl: "http://o/food" });
  await insertChannel(db, { id: "channel_yoga", name: "Yoga", originUrl: "http://o/yoga" });
  await insertChannel(db, { id: "channel_art", name: "Art", originUrl: "http://o/art" });
});

describe("ensureSession channel rebind (PRD §41 channel-switch extension)", () => {
  it("keeps the original channel across repeated ensures for the ordinary single-channel case", async () => {
    await ensureSession(db, { id: "sess_a", channelId: "channel_food", deviceType: "web", country: "IN" });
    await ensureSession(db, { id: "sess_a", channelId: "channel_food", deviceType: "web", country: "IN" });
    const sess = await getSession(db, "sess_a");
    expect(sess).toMatchObject({ channelId: "channel_food", deviceType: "web", country: "IN" });
  });

  it("updates the recorded channel when the same session id is re-ensured under a new channel", async () => {
    await ensureSession(db, { id: "sess_b", channelId: "channel_food", deviceType: "web", country: "IN" });
    await ensureSession(db, { id: "sess_b", channelId: "channel_yoga", deviceType: "web", country: "IN" });
    const sess = await getSession(db, "sess_b");
    expect(sess?.channelId).toBe("channel_yoga");
  });

  it("keeps updating across more than one switch — always reflects the latest, not the first or second", async () => {
    await ensureSession(db, { id: "sess_c", channelId: "channel_food" });
    await ensureSession(db, { id: "sess_c", channelId: "channel_yoga" });
    await ensureSession(db, { id: "sess_c", channelId: "channel_art" });
    const sess = await getSession(db, "sess_c");
    expect(sess?.channelId).toBe("channel_art");
  });

  it("preserves the session's original createdAt across a channel rebind (this is an update, not a new row)", async () => {
    await ensureSession(db, { id: "sess_d", channelId: "channel_food" });
    const first = await getSession(db, "sess_d");
    await ensureSession(db, { id: "sess_d", channelId: "channel_yoga" });
    const second = await getSession(db, "sess_d");
    expect(second?.createdAt).toBe(first?.createdAt);
  });
});
TESTFILE

cat > packages/control-plane/src/session-channel-rebind.test.ts <<'TESTFILE'
import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";
import { newDb } from "pg-mem";
import { MemoryPodCache, type Pool } from "@ssai/persistence";
import { MemoryObjectStore } from "@ssai/storage";
import { buildServer } from "./server.js";

const here = dirname(fileURLToPath(import.meta.url));
const MIG_DIR = resolve(here, "../../../migrations");
const SCHEMA = readdirSync(MIG_DIR)
  .filter((f) => f.endsWith(".sql"))
  .sort()
  .map((f) => readFileSync(join(MIG_DIR, f), "utf8"))
  .join("\n");

function build() {
  const mem = newDb();
  mem.public.none(SCHEMA);
  const { Pool } = mem.adapters.createPg();
  const pool = new Pool() as unknown as Pool;
  const store = new MemoryObjectStore();
  const app = buildServer({ pool, podCache: new MemoryPodCache(), store, logger: false, authDisabled: true });
  return { app, store };
}

describe("session channel rebind across a live channel switch (PRD §41 extension)", () => {
  it("a session that continues onto a new channel via /v1/ad-decision reports the new channel, not the one it started on", async () => {
    const { app } = build();

    await app.inject({ method: "POST", url: "/v1/channels", payload: { id: "channel_food", name: "Food", origin_url: "http://o/food" } });
    await app.inject({ method: "POST", url: "/v1/channels", payload: { id: "channel_yoga", name: "Yoga", origin_url: "http://o/yoga" } });

    const first = await app.inject({
      method: "POST",
      url: "/v1/ad-decision",
      payload: { session_id: "sess_switch", channel_id: "channel_food", opportunity_id: "opp_food_1", duration: 30 },
    });
    expect(first.statusCode).toBe(200);

    // Same session id, a later avail on a different channel — a real integration that keeps one
    // session for a whole multi-channel viewing session, not a bug in the caller.
    const second = await app.inject({
      method: "POST",
      url: "/v1/ad-decision",
      payload: { session_id: "sess_switch", channel_id: "channel_yoga", opportunity_id: "opp_yoga_1", duration: 30 },
    });
    expect(second.statusCode).toBe(200);

    const sess = await app.inject({ method: "GET", url: "/v1/sessions/sess_switch" });
    expect(sess.statusCode).toBe(200);
    expect(sess.json()).toMatchObject({ channelId: "channel_yoga" });
  });

  it("still reports the right channel for a session that never switches (ordinary single-channel case)", async () => {
    const { app } = build();
    await app.inject({ method: "POST", url: "/v1/channels", payload: { id: "channel_food", name: "Food", origin_url: "http://o/food" } });

    await app.inject({
      method: "POST",
      url: "/v1/ad-decision",
      payload: { session_id: "sess_steady", channel_id: "channel_food", opportunity_id: "opp_food_1", duration: 30 },
    });
    await app.inject({
      method: "POST",
      url: "/v1/ad-decision",
      payload: { session_id: "sess_steady", channel_id: "channel_food", opportunity_id: "opp_food_2", duration: 30 },
    });

    const sess = await app.inject({ method: "GET", url: "/v1/sessions/sess_steady" });
    expect(sess.json()).toMatchObject({ channelId: "channel_food" });
  });
});
TESTFILE

if npx vitest run --config /tmp/trusted.vitest.config.mjs \
  packages/persistence/src/session-channel-rebind.test.ts \
  packages/persistence/src/repositories.test.ts \
  packages/control-plane/src/session-channel-rebind.test.ts \
  packages/control-plane/src/server.test.ts \
  > /logs/verifier/vitest.log 2>&1; then
  success=1.0
  success_int=1
else
  success=0.0
  success_int=0
fi

# NOTE: correct_diagnosis/policy_compliance/side_effect_safety are placeholders (fixed at 1.0),
# same as task-01/02/05/06 — no automated side-effect-safety check exists yet in this world.
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
