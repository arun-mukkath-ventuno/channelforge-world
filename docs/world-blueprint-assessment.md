# External world-readiness assessment (2026-09-03)

Condensed from `FAST-World-Docker-and-Harbor-Blueprint.md`, an external review of the three
upstream repos' architecture/PRD docs (not a checkout+execution audit) commissioned outside this
session. Kept here, in-repo, so the replan doesn't depend on a file living only in `~/Downloads`.
Cross-check anything load-bearing against source before acting on it — this was a docs-only
review, same caveat this repo's own docs carry.

## Verdict

The three applications are ready for "world-productization" but this repo (`channelforge-world`)
is **not yet a reproducible RL world** — it's missing a fourth layer: a sealed, deterministic,
resettable, observable evaluation appliance. Line count (~80K LOC across 3 repos) says nothing
about world quality; that's measured by startup reliability, deterministic reset, task isolation,
verifier strength, runtime cost, and whether tasks actually discriminate between agents.

| Layer | Assessment |
|---|---|
| Individual applications | Strong MVPs, deployed |
| Cross-repo product loop | Working for channels 101 and 102 (confirmed independently — see `docs/ecosystem.md`'s corrected sections) |
| Full five-channel showcase | Partial — 2/5 real, 3/5 still public test streams |
| Deterministic offline world | Not built |
| Harbor benchmark dataset | Not built |

Recommendation: **one versioned world release** (several service images + a Compose topology),
not one monolithic image — preserves process isolation, health diagnosis, caching, and per-task
selective rebuilds.

## What's real vs. still a gap, per repo

**ChannelForge**: delivery-grade HLS origin, SCTE-35 DATERANGE + legacy cue tags, XMLTV/TV-Anytime/
now-next, distribution/certification/webhooks/NOC/reconciliation, real per-break SSAI ingestion.
Gaps: redundant primary/backup output unsoaked, ABR is single-rendition only, captions are WebVTT
only, frame-accurate cue boundaries incomplete, some planning docs still describe Phase B/C as
not-started (doc drift, not necessarily a code gap — same pattern this repo's own `ecosystem.md`
status note just corrected).

**ssaiadserver**: deterministic cue parsing/eligibility/pod-build/slate-fill/signed sessions,
Postgres+Redis+S3-compatible storage, real stitching, 115-test suite. Gaps: reproducibility still
depends on ChannelForge's media-sequence/timing/break-identity; a creative-prep discrepancy
(poll loop in deployment vs. drain CLI in the PRD) needs resolving; VAST/OpenRTB/DRM/DASH/
multi-CDN deliberately out of scope (shouldn't block the first world).

**fast-world-tv**: channels 101/102 genuinely live (real ChannelForge streams, real XMLTV, real
SSAI sessions, playhead ad beacons + audience/QoE telemetry). Gaps: channels 103–105 still public
test streams + generated schedules; some marketing figures/EPG-freshness numbers simulated; the
app is Vercel-oriented (world needs a local Node container + local durable store); admin can't set
`ssaiChannel` on a *new* channel, only preserve an existing one.

## What a real "world" layer needs that this repo doesn't have yet

1. **`world-control` service** — `world ready` / `world reset --seed N` / `world clock set|advance`
   / `world scenario apply NAME` / `world fault start|stop NAME` / `world snapshot` / `world doctor`.
   Nothing like this exists in `world/` today — the closest analogue is each service's own
   restart-verb script (`restart-api.sh` etc.), which is per-process, not world-level seed/reset/
   time/fault control.
2. **Virtualized time** — one clock abstraction threaded through schedule generation, campaign
   eligibility, token expiry, telemetry, verifier polling. Not present anywhere in this world.
3. **Stable HLS identity** — seeded media sequence, discontinuity sequence, schedule version,
   break IDs (no wall-clock-derived or random IDs) — needed for deterministic reset/replay.
4. **Deterministic, idempotent reset** — two resets must produce byte-equivalent seeded state.
   Not attempted yet; this world today re-vendors + rebuilds, it doesn't reset a running world.
5. **No-network enforcement** — flagged as a hard release gate here; this repo's own
   `docs/harbor-install.md` already tracks this as a known, still-open gap.
6. **Separate verifier image/environment** (`environment_mode = "separate"` in `task.toml`,
   `[verifier.environment]` with its own `docker_image`) — task-01..04's verifiers all run inline
   in `tests/test.sh` inside the agent's own container today, not isolated.
7. **Selective rebuilds** — a task touching only ssaiadserver shouldn't force a ChannelForge +
   fast-world-tv rebuild. Not evaluated one way or the other yet for this world's Dockerfiles.

## Proposed task portfolio (for replan reference — not committed to)

Strong-task bar: spans ≥2 components with a bounded outcome, ~30–120 min for an experienced
engineer, multiple plausible root causes with a deterministic verifier, verifiable in <5–8 min
with no network, graded on external behavior + regression tests (not diff similarity), can't be
gamed by disabling auth/suppressing errors/hardcoding IDs/editing tests/canned responses.

**Tier 1** (build first): FW-001 alternate CUE-OUT syntax losing `break_id` correlation
(ChannelForge+SSAI) · FW-002 underfilled ad pod / playback continuity (SSAI+TV) · FW-003
channel-switch session/beacon bleed (TV+SSAI) · FW-004 rights-takedown/guide/playout consistency
(ChannelForge+TV, hard) · FW-005 origin restart mid-break (all three, hard).

**Tier 2** (after the world is stable): FW-006 idempotent duplicate/reordered ad events ·
FW-007 DATERANGE/CUE-tag reorder reconciliation · FW-008 failover without rewind (very hard) ·
FW-009 campaign boundary expiry · FW-010 real vs. simulated as-run delta.

Full specs (agent prompt, seeded defect, hidden-verifier checklist, anti-gaming notes) for
FW-001..005 are in the source file, not reproduced here — read it directly if/when a specific one
of these gets picked up for authoring.

## Verifier design principles worth adopting regardless of which tasks get built

- Reward as weighted dimensions, not one pass/fail: target behavior (0.55), regression safety
  (0.20), cross-service invariants (0.15), failure behavior (0.10) — binary headline + diagnostic
  submetrics for a leaderboard, full numeric dimensions for training rollouts.
- Three evidence planes per verifier: black-box (HTTP/manifest/playback probe), durable state
  (read-only DB/event assertions), regression (existing tests + a small hidden contract suite).
- No LLM judge for anything programmatically checkable.
- Randomize fixture IDs/seeds per run; verify health of all required services post-patch; detect
  disabled tests / replaced binaries / canned endpoints / origin-or-SSAI bypass; cap logs/timeouts;
  save manifests/events/logs/playback trace on failure.

## Release gates (before calling any of this v0.1)

20/20 clean cold starts+resets · zero runtime network access · same seed ⇒ equivalent
schedule/break/pod/event snapshots across runs · oracle passes every task, no-op fails every task
· ≥2 plausible wrong fixes fail each hidden verifier · verifier duration <8 min/task · no task
exposes hidden tests/gold patches/production secrets · failure artifacts make a false negative
diagnosable · first 3 tasks run against ≥2 agent families and calibrated.

## Suggested milestone order (source doc's own delivery plan)

0. Executable audit (2–4 days): pin all 3 SHAs, run every existing test suite, resolve doc/code
   contradictions into a capability ledger, capture the current 2-channel golden trace.
1. Deterministic world MVP (1–2 wks): shared Compose topology + local fast-web image, world
   control + virtual time + reset + fixtures + health checks, remove all public/cloud runtime
   deps, prove 20 consecutive cold starts/resets.
2. First benchmark slice (1–2 wks): FW-001..003 with private gold patches, separate verifier
   images, failure artifacts, oracle/no-op/bad-patch runs.
3. Calibration (1 wk): multiple agent families/seeds, reject near-0%/near-100% tasks (unless
   deliberately tiered), target ~30–70% pass rate on a strong agent.
4. Showcase (~1 wk): FW-004/005, viewer-visible replay of symptom→patch→restored playback→
   verifier evidence, publish a benchmark card (versions, contamination policy, resources,
   attempts, scoring, known limitations).
