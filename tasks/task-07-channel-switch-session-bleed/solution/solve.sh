#!/usr/bin/env bash
# Oracle — reference fix, used only to validate the task is solvable. Never shown to the agent.
#
# Root cause: playback_sessions rows are created via an idempotent "ensure" INSERT so the same
# session id can be safely re-presented across many requests (every /v1/ad-decision call does
# this). But that INSERT uses `ON CONFLICT (id) DO NOTHING` — so the very first channel_id a
# session is ever created with is permanent. When a session legitimately continues under a
# different channel (a client integration that keeps one session id for a whole multi-channel
# viewing session, calling /v1/ad-decision with a new channel_id per channel change rather than
# requesting a fresh /v1/sessions each time — a real, already-supported path: /v1/ad-decision
# accepts a caller-supplied session_id and always re-ensures the session with whatever channel_id
# is in that request), the playback_sessions row silently keeps the original, now-stale channel_id
# forever, even though every opportunity/decision/event from that point on is correctly recorded
# under the new channel (those don't derive their channel from the sessions table — they're
# written with the request's own channel_id directly). Any report or lookup that trusts
# sessions.channel_id as "which channel is this session on" is wrong for the rest of that
# session's life.
#
# Fix, one file: packages/persistence/src/repositories/sessions.ts — ensureSession's upsert
# updates channel_id (and bumps last_activity_at) on conflict instead of doing nothing, so the
# session's recorded channel always reflects the most recent one it was ensured under. No history
# is kept (not asked for); decisioning/opportunities/events are untouched (already correct).
set -euo pipefail
cd /app

# Exact string replacement rather than a hand-built unified diff — the one-line change is
# unambiguous and this avoids hunk line-count mistakes. Node (not python3) is what's actually
# on this image.
node - <<'JS'
const fs = require("fs");
const path = "packages/persistence/src/repositories/sessions.ts";
const src = fs.readFileSync(path, "utf8");
const oldBlock = [
  "/** Create the session if absent; idempotent so ad-decision can ensure it exists. */",
  "export async function ensureSession(db: Queryable, input: SessionInput): Promise<void> {",
  "  await db.query(",
  "    `INSERT INTO playback_sessions (id, channel_id, device_type, country, anonymous_id, ip_hash, user_agent)",
  "     VALUES ($1, $2, $3, $4, $5, $6, $7)",
  "     ON CONFLICT (id) DO NOTHING`,",
].join("\n");
const newBlock = [
  "/** Create the session if absent; idempotent so ad-decision can ensure it exists. Re-presenting",
  " *  an existing session id with a different channelId (a session legitimately continuing under",
  " *  a new channel) updates the recorded channel to the latest one — PRD §41's channel-switch",
  " *  extension — rather than leaving it pinned to whichever channel the session first saw. */",
  "export async function ensureSession(db: Queryable, input: SessionInput): Promise<void> {",
  "  await db.query(",
  "    `INSERT INTO playback_sessions (id, channel_id, device_type, country, anonymous_id, ip_hash, user_agent)",
  "     VALUES ($1, $2, $3, $4, $5, $6, $7)",
  "     ON CONFLICT (id) DO UPDATE SET",
  "       channel_id = EXCLUDED.channel_id,",
  "       last_activity_at = now()`,",
].join("\n");
if (!src.includes(oldBlock)) throw new Error("expected block not found — sessions.ts must have changed upstream");
fs.writeFileSync(path, src.replace(oldBlock, newBlock));
JS

npm run build
restart-ssai
