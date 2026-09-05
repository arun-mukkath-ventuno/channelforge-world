# The ecosystem: ChannelForge + ssaiadserver + fast-world-tv

This world grew from wrapping one service (ChannelForge) to wrapping the three repos that talk
to each other in production. This doc is the integration-contract reference so a task author
never has to re-derive it from source: what each repo actually expects from the others, the two
places those contracts didn't line up out of the box (and the small patches that bridge them),
and what's still missing before the pipeline is *live*, not just wired.

## Status note (2026-09-03) — upstream has moved well past our pins; this doc is being reconciled

All three upstream repos shipped a burst of new work since the pins below were set:
**ChannelForge is 43 commits ahead**, **ssaiadserver 10**, **fast-world-tv 11** (checked directly
against each repo's own `git log`, not yet re-vendored into `vendor/`). The headline change is
that a real, live, two-channel path now exists in production — ChannelForge → ssaiadserver →
fast-world-tv genuinely airs for channels 101 (Home Cooking) and 102 (Yoga & You), with SSAI
ad-stitched playback, ad/audience telemetry, and per-break reconciliation — not simulated. This
supersedes some of what's written below; corrections are called out inline where a section is now
known-stale rather than rewriting the whole doc. Two independent reviews converged on the same
picture: an external readiness assessment (condensed into `docs/world-blueprint-assessment.md`)
and a direct diff of the three repos' new commits.

Known corrections so far:
- **ChannelForge → ssaiadserver is no longer fully unwired** (see the section below) — a new read
  path (`GET /v1/reconciliation/breaks`, per-break) is live as of ChannelForge's telemetry-blueprint
  commits (#173–#176); the write path (`POST /v1/ad-decision`) is still unwired.
- **fast-world-tv's ChannelForge integration is real for channels 101/102**, not the
  guide/status-proxy shape this doc originally described — see the corrected section below.
- fast-world-tv's own `README.md` still says its schedule data "stands in for ChannelForge...
  remains simulated until Phase 3" — that's now doc drift on the *upstream* repo's side, not
  something wrong in this doc; noted here so a task author doesn't trust that README claim as-is.
- Re-vendoring (`scripts/vendor-source.sh` + bumping the three `PINNED_COMMIT_*` files) has not
  happened yet — that's part of the replan, not done as part of this doc update.

**2026-09-05 update**: the repos moved again — ChannelForge now 46 commits ahead, ssaiadserver 11,
fast-world-tv 17 (current HEADs `3c5599a`/`3ce4632`/`6d09506`). Two changes worth flagging before
the next re-vendor:
- **All 5 channels are now real**, not 2 of 5 — fast-world-tv wired channels 103 (Art All The Way)
  and 104 (Ventuno Mix, replacing the retired "Food Shorts TV") to live ChannelForge origins + SSAI
  sessions, same pattern as 101/102. Closes the gap `docs/world-blueprint-assessment.md` flagged.
- **fast-world-tv's channel API is now async and store-backed** (`6d09506`, the "v2 app shell"
  rebuild) — `getChannel`/`listChannels`/`guide` read an admin-editable `channel-config-store` and
  return Promises, where they used to read a static `CHANNELS` array synchronously. Any code that
  vendors against the old sync shape needs updating.
- ChannelForge shipped `e9d86a9` "globally-unique interval-break ids" (break-identity correctness)
  and `4c99050` (real rights management — policies/assignments/takedowns) — both relevant to
  `docs/poc-scope.md`'s task authoring (FW-001 and FW-004 respectively; see that doc's rescope log).
- ssaiadserver added a VAST ingestion slice (`3ce4632`) and a from-scratch admin console — real
  capability, not currently pulled into POC task scope.

**2026-09-05 — re-vendored to current HEADs and re-verified.** Pins bumped to ChannelForge
`cdbf80b` (VAST slice 4), ssaiadserver `24c21d4` (VAST slices 2-3 + real CF↔SSAI origin wiring +
CORS fix), fast-world-tv `09193c2` (cue-out/cue-in player UI) — the exact `3c5599a`/`3ce4632`/
`6d09506` targets above plus what landed on top by the time this ran. `scripts/vendor-source.sh`
re-run clean; `docker compose -f world/docker-compose.yaml up -d --build` brings up all 9 services
healthy (see "Verified so far" below, updated). Both glue patches (`world/patches/
channelforge-ssai-base-url.patch` and `world/patches/ssaiadserver-manifest-template.patch`) are
now **retired and deleted** — see "The two gaps that needed patching" below, rewritten to match.
task-01..04 re-verified against the new pins before archiving (see each task's section) — task-01
still passes clean; task-02/03/04 all broke, each for a genuine, diagnosed upstream-drift reason,
not a harness or archiving-process bug. All four are now archived under `archive/old/tasks/`
(`docs/poc-scope.md` Step 2).

## The pipeline

```
ChannelForge (schedule + playout-worker)
  --HLS origin, SCTE markers-->  ssaiadserver data-plane (avail detect + ad stitch)
  --stitched manifest-->         fast-world-tv (viewer)
```

## Repos and pins

Same determinism model as ChannelForge alone had: one `PINNED_COMMIT_<SERVICE>` file per repo,
pulled by `scripts/vendor-source.sh` via `git archive` (never a moving branch). Override the
source checkout path with `CHANNELFORGE_REPO` / `SSAIADSERVER_REPO` / `FASTWORLDTV_REPO`.

`PINNED_COMMIT_CHANNELFORGE` was bumped from task-01's original pin (`6ce2b1e`) to `b46733b` (52
commits later) — the original pin predates all of PRD 3.0 (FAST/SCTE/SSAI/EPG), so none of that
code existed in the old vendor snapshot. `task-01`'s regression patch was re-verified to still
apply and reverse byte-identically at that pin (`app/services/rights.py` is unchanged across those
52 commits), so this didn't require touching task-01.

**2026-09-05: bumped again**, to ChannelForge `cdbf80b`, ssaiadserver `24c21d4`, fast-world-tv
`09193c2`. `task-01` was re-verified once more (`harbor run -a oracle` → `task_success: 1.0`) —
`app/services/rights.py` is still untouched. `task-02`/`03`/`04` were **not** carried forward
clean — see their sections below for what broke and why.

## Integration contracts (as they actually exist upstream)

### ChannelForge → ssaiadserver

`apps/api/app/adapters/ssai_adserver.py`'s `SsaiAdServerAdapter` implements two ssaiadserver
routes:

```
POST /v1/ad-decision              {channel_id, opportunity_id, duration, [session_id], [seed]} -> {pod_id, ...}
GET  /v1/reconciliation/breaks    per-break delivery rows, keyed by externalBreakId = break_id
```

**Corrected 2026-09-03 — this is now half-live, not fully unwired.** The write path
(`POST /v1/ad-decision`, driving a real-time ad decision) is still not called from any live
ChannelForge path — `get_ssai_adapter` is still only constructed in tests/registry, same as
before. But a **new read path is genuinely live**: ChannelForge's §17 reconciliation now fetches
`GET /v1/reconciliation/breaks` for real (`apps/api/app/services/ssai_delivery.py`, wired from
`reconciliation_wiring.assemble_inputs` with `include_ssai` on by default), matching ssaiadserver's
own new `GET /v1/reconciliation/breaks` endpoint (`9a943c5`). This uses ChannelForge's own admin
auth against ssaiadserver's console (`ssai_base_url`/`ssai_admin_user`/`ssai_admin_password`,
env `CF_SSAI_BASE_URL`/`CF_SSAI_ADMIN_USER`/`CF_SSAI_ADMIN_PASSWORD` — see
`apps/api/app/services/ssai_analytics.py`), **not** the `SSAI_ADSERVER_BASE_URL`/`base_url`+
`transport` shape `SsaiAdServerAdapter` itself takes. Best-effort: an empty leg when SSAI is
unconfigured/unreachable, so reconciliation still runs on ChannelForge-owned records alone.

**This superseded glue patch #2 below** (`world/patches/channelforge-ssai-base-url.patch`,
`CF_SSAI_ADSERVER_BASE_URL`/`ssai_adserver_base_url`) — upstream built its own real config field
and live wiring using a different name and a different (analytics/reconciliation) mechanism, not
the one our forward-looking patch guessed at. **2026-09-05: that patch is now retired and
deleted** — `world/docker-compose.yaml`'s `main` service sets the real `CF_SSAI_BASE_URL`/
`CF_SSAI_ADMIN_USER`/`CF_SSAI_ADMIN_PASSWORD` env vars instead, and `ssai-control` sets matching
`ADMIN_USER`/`ADMIN_PASSWORD`; verified end-to-end with a real login (`POST /admin/api/login`
from inside `main`'s own env values returns `200` + a session cookie). Treat "ChannelForge reads
SSAI's per-break reconciliation data" as a real, verifiable signal now; "ChannelForge requests an
ad decision from SSAI" is still not.

### ssaiadserver ← ChannelForge (the direction that's actually live)

ssaiadserver's `packages/data-plane/src/origin.ts` `OriginClient` is the real, tested, working
half: it polls `{CHANNELFORGE_ORIGIN_URL}/{channel}/{variant}.m3u8` on a TTL cache and serves
last-good on failure. `packages/core/src/scte.ts`'s `parseMarkerLine` (called from
`detectAvails`) accepts either marker style in the manifest:

```
#EXT-X-CUE-OUT[:DURATION=N]  ...  #EXT-X-CUE-OUT-CONT (ignored)  ...  #EXT-X-CUE-IN
#EXT-X-DATERANGE:ID=...,DURATION=N,SCTE35-OUT=0x...
```

ChannelForge's actual cue synthesis is `services/playout-worker/worker/scte35.py`:
`daterange_out`/`daterange_in` render real, CRC-valid MPEG-2 `splice_info_section`s (a
`splice_insert` command) as `EXT-X-DATERANGE` tags with hex-encoded `SCTE35-OUT`/`SCTE35-IN` —
this is the DATERANGE style above, and it's what a cross-repo SCTE-format task should exercise.

### ChannelForge ↔ fast-world-tv

**Corrected 2026-09-03.** ADR-9's originally-planned `/api/fast/guide`/`/api/fast/status` proxy
shape (below) was never built; instead, two of five channels were wired directly and concretely
in `src/lib/channels.ts`, one field at a time, per real ChannelForge output:

| Channel | `hlsUrl` | `epgUrl` | `ssaiChannel` |
|---|---|---|---|
| 101 Home Cooking | real ChannelForge origin (`forge.ventunotech.com/hls/<output_id>/delivery_master.m3u8`) | real ChannelForge public EPG URL | `channel_homecooking` — player plays the SSAI ad-stitched session, not `hlsUrl`, when set |
| 102 Yoga & You | same shape, different `output_id`/EPG | same | `channel_yoga` |
| 103–105 | public test streams | generated/local | unset |

So the live signal for a task isn't a proxy endpoint to fetch through — it's per-channel config in
`channels.ts` (`hlsUrl`, `epgUrl`, `ssaiChannel`) pointing at real ChannelForge/ssaiadserver
outputs for exactly two of five channels, and the player (`FastPlayer`) branching on whether
`ssaiChannel` is set to decide whether to request an SSAI session or play `hlsUrl` directly,
firing playhead-based ad beacons when it does. The originally-planned `/api/fast/guide` /
`/api/fast/status` proxy endpoints described below were never built this way and remain local
synthetic data for all five channels regardless of `hlsUrl`/`epgUrl` wiring — guide/status data
and playback data took two different, independent wiring paths upstream.

Original ADR-9 design (pull-based, per `channelforge/docs/adr/0009-pilot-distributor-target.md`)
for reference — **not what actually got built**:

| fast-world-tv side | ChannelForge side |
|---|---|
| per-channel `hlsUrl` | `{CF_ORIGIN_BASE_URL}/{output_id}/delivery_master.m3u8` (`apps/api/app/services/fast.py`) |
| `/api/fast/guide` (JSON EPG) | `GET /organizations/{org_id}/fast/guide` |
| `/api/fast/status` | `GET /organizations/{org_id}/fast/status` |

Wiring `/api/fast/guide`/`/api/fast/status` as real proxies (or deciding the per-channel-field
approach is the permanent design, since it's what shipped) is still an open question for the
replan — not required to prove the schedule→origin→SSAI→playback pipeline, and still deferred
here.

## The two gaps that needed patching — both now retired (2026-09-05)

Both of the world's original glue patches turned out to be superseded by upstream building the
same bridge itself, for real, in its own code. Neither patch applies cleanly against the current
pins any more, and both are now deleted from `world/patches/`.

1. **Origin URL shape mismatch** (was: ChannelForge serves `{base}/{output_id}/delivery_master.
   m3u8`; ssaiadserver's `OriginClient` default is `{base}/{channel}/{variant}.m3u8`). The old
   bridge, `world/patches/ssaiadserver-manifest-template.patch`, added an env-configurable
   `CHANNELFORGE_MANIFEST_PATH_TEMPLATE` to `origin.ts`. Upstream `origin.ts` has since grown its
   own, more general mechanism: `originMap`/`CHANNELFORGE_ORIGIN_MAP` (a JSON channel→full-URL
   override), which is what the old patch's single hunk now fails against (`Hunk #1 FAILED at
   38`) — confirmed by reading the current file, not just the patch-apply error. Not currently
   wired to a real value in `world/docker-compose.yaml`'s `ssai-data`, because **no route in this
   world serves `delivery_master.m3u8` yet** (see "Known gaps" — no playout-worker/object-storage
   edge), so there's no real per-channel URL to put in the map. When that gap closes, wire
   `CHANNELFORGE_ORIGIN_MAP` directly — no local patch needed any more.
2. **No `SSAI_ADSERVER_BASE_URL` in ChannelForge** (was: `SsaiAdServerAdapter` needs a `base_url`
   + `transport` injected by its caller; nothing in `apps/api/app/config.py`/`registry.py` did
   that outside tests). The old bridge, `world/patches/channelforge-ssai-base-url.patch`, added
   `ssai_adserver_base_url`/`CF_SSAI_ADSERVER_BASE_URL` plus a `get_configured_ssai_adapter()`
   factory — but nothing on any live ChannelForge call path ever invoked it; it was forward-looking
   glue for a feature that never got wired that way. Upstream instead built the real thing under a
   different name for a different purpose: `CF_SSAI_BASE_URL`/`CF_SSAI_ADMIN_USER`/
   `CF_SSAI_ADMIN_PASSWORD` (`app/services/ssai_analytics.py`), used for admin-cookie-authenticated
   telemetry analytics and break-delivery reconciliation (see "ChannelForge → ssaiadserver" above)
   — now wired for real in `world/docker-compose.yaml` and verified end-to-end (see above).
3. **ChannelForge's FAST feature flags default off.** `CF_DELIVERY_ORIGIN` (delivery-grade HLS
   origin packaging) and friends (`CF_OUTPUT_PROBES`, `CF_REDUNDANT_OUTPUTS`,
   `CF_ASRUN_AUTHORITY`, `CF_OUTPUT_FAILOVER`) are plain `os.environ.get(...) == "1"` reads in
   `services/playout-worker` / `apps/api/app/jobs/scheduler.py` — no patch needed, just set them
   on whichever service needs live-pipeline behavior. Only turn on what a given task actually
   needs; a single-output channel is byte-identical with all of them off.

## Verified so far

`docker compose -f world/docker-compose.yaml up -d` brings up all 9 services (ChannelForge
`main`/`scheduler`/`postgres`/`redis`, ssaiadserver `ssai-control`/`ssai-data`/`ssai-postgres`/
`ssai-redis`, and `fast-web`) cleanly; each of the four HTTP-facing services responds
(`main:8000/docs`, `ssai-control:4000/v1/channels`, `ssai-data:4010`, `fast-web:3000/api/fast/
channels`); and each of the four restart verbs (`restart-api`, `restart-ssai` on both ssai
services, `restart-fast-web`) runs end to end — including the TypeScript rebuild for ssaiadserver
and the `next build` for fast-web — and the service comes back up serving afterward. This proves
the compose wiring, the two glue patches, and the restart-verb contract; it does **not** yet prove
the live pipeline (see the object-storage/edge gap below).

**2026-09-05, re-verified at the new pins, glue patches retired**: `docker compose -f world/
docker-compose.yaml up -d --build` again brings up all 9 services healthy from a clean build.
`main:8000/health`, `ssai-control:4000/health`, `ssai-data:4010/health` all return `{"status":
"ok", ...}`; `fast-web:3000/` returns a `307` (Next.js redirect, expected). The real SSAI admin
wiring that replaced glue patch #2 was exercised directly: `POST http://localhost:4000/admin/api/
login` with the `world-ssai-admin`/`world-ssai-admin-secret` credentials set in compose returns
`200` + a session cookie, confirming `CF_SSAI_BASE_URL`/`ADMIN_USER`/`ADMIN_PASSWORD` line up
end-to-end between `main` and `ssai-control`.

## First task built on this: task-02

**Archived 2026-09-05** to `archive/old/tasks/task-02-daterange-avail-detection/` (`docs/
poc-scope.md` Step 2) — no longer part of the default `tasks/` sweep. Re-verification at the
`cdbf80b`/`24c21d4`/`09193c2` pins found genuine upstream drift: `harbor run -a oracle` now scores
`task_success: 0.0` (build succeeds; `avails.test.ts`'s "detects an avail from real ChannelForge
DATERANGE cues" case fails, `expected [] to have a length of 1 but got +0`). ChannelForge's real
`worker/scte35.py` DATERANGE cue output has changed shape since this task's fixture was captured
from it, and `detectAvails` no longer recognizes the new shape — a real, second-generation defect
in the same area this task originally fixed, not a harness problem. Left as-is rather than
re-fixed, since the task itself is being retired; a fresh task against current output would be the
right way to pick this back up, not a patch to the archived one.

`tasks/task-02-daterange-avail-detection` fixes a real, confirmed defect found while writing
this doc: ssaiadserver's `detectAvails` (`packages/data-plane/src/avails.ts`) only opens/closes
an avail on `cue_out`/`cue_in` marker kinds — it silently ignores `daterange`-kind markers
entirely (confirmed: pristine `avails.test.ts` has zero DATERANGE test cases). Since DATERANGE is
ChannelForge's *only* real cue-signalling format (`worker/scte35.py` → `worker/cue_schedule.py` →
`worker/origin_runner.py`, confirmed fully wired at current HEAD despite a stale docstring in
`origin.py` claiming otherwise), **no avail is ever detected on any real ChannelForge channel** —
every ad break plays through as pass-through slate, forever.

The fix is single-repo (ssaiadserver only — ChannelForge's side is already correct), so this task
uses the single-repo write-boundary model, not the colocated cross-repo one, even though it's
cross-repo *verified*: `tests/test.sh` grades against a manifest fixture built from ChannelForge's
actual `scte35.daterange_out`/`daterange_in` output (captured directly from the real functions,
not hand-typed), not a synthetic one. There is no `setup/regression.patch` — the defect is already
present in pristine vendored source, so the task is framed as a missing-behavior bug report (the
README's own stated scope: "a bug report or feature request"), and `solution/solve.sh` applies a
real forward fix rather than reversing a regression. Verified through real Harbor: `oracle` →
`task_success: 1.0`, `nop` → `0.0`.

A genuinely two-repo-writable task (the colocated-`main` model in `docs/workflow.md`) is still an
open item — this defect didn't turn out to need one. See task-01 for the reversible-regression
shape, task-02 for the missing-behavior shape; task-03 below is that colocated-model task.

## The two-repo-writable task: task-03

**Archived 2026-09-05** to `archive/old/tasks/task-03-org-scoped-origin-drift/` (`docs/
poc-scope.md` Step 2) — no longer part of the default `tasks/` sweep. Re-verification at the
`cdbf80b`/`24c21d4`/`09193c2` pins found a genuine build-time break, not a verifier regression:
this task's own `environment/Dockerfile` bakes in the (now-retired, see "The two gaps that needed
patching" above) `world/patches/ssaiadserver-manifest-template.patch`, which no longer applies —
`patch -p1` fails with `Hunk #1 FAILED at 38` against `origin.ts`'s new `originMap`/
`CHANNELFORGE_ORIGIN_MAP` shape. `harbor run -a oracle` fails at the docker-compose build step
(`RuntimeError`), before the agent/verifier ever run. Confirms the "gaps that needed patching"
section's superseded-by-upstream finding independently — this is the same origin.ts drift, hit
from the task side rather than the world side. Not re-fixed, since the task is being retired.

`tasks/task-03-org-scoped-origin-drift` is the first task using the colocated-`main` model. The
real cross-repo integration surface investigated for it (ChannelForge's dead/unwired
ad-decision + reconciliation adapter, see `SsaiAdServerAdapter.import_delivery` vs.
ssaiadserver's `GET /v1/analytics`) turned out to be genuinely mismatched but entirely unreached
by any live ChannelForge call path — a real gap, but authoring a task around it would mean
scaffolding a feature that doesn't exist yet, not fixing a regression. Given that, this task is a
**synthetic two-sided regression** — deliberately not held to the "real, confirmed defect" bar
task-01/02 used — built on the one integration surface that *is* genuinely live: the origin path
both ChannelForge (`fast.py`'s `origin_urls`) and ssaiadserver (`origin.ts`'s `OriginClient`)
must agree on byte-for-byte.

The scenario: ChannelForge starts scoping origin delivery paths by organization
(`{org_id}/{output_id}/delivery_master.m3u8`, for multi-tenant isolation on a shared origin
edge) via a new optional `org_id` parameter on `origin_urls` — not yet wired into
`build_status`/`build_guide`'s call sites, so this doesn't disturb any pristine test. Two
independent bugs ship with it, one per repo:

1. **ChannelForge**: `origin_urls`'s org-scoped branch puts `org_id` *after* `output_id`
   instead of before it.
2. **ssaiadserver**: `OriginClient`'s `CHANNELFORGE_MANIFEST_PATH_TEMPLATE` mechanism (our own
   glue code, `world/patches/ssaiadserver-manifest-template.patch`) gained a `CHANNELFORGE_ORG_ID`
   env var, but the org id is appended as a `?org=` query string instead of substituted into a
   `{org}` template placeholder.

Verified strictly two-sided by hand before trusting the Oracle: with only the ChannelForge fix
applied, the task's verifier still fails (`ssaiadserver_ok=0`); with only the ssaiadserver fix
applied, it still fails (`channelforge_ok=0`); both together pass. The verifier itself is
code-level, not live-HTTP — a new pytest file asserting `origin_urls`'s exact org-scoped output,
and a new vitest file asserting `OriginClient` requests the byte-identical URL for the same
inputs, both written at verify time only, run alongside each repo's own pre-existing relevant
test file. No live server is needed (no playout-worker origin exists to fetch from yet — see
"Known gaps" below), so this task has no restart verb. Verified through real Harbor: `oracle` →
`task_success: 1.0` (all four metrics), `nop` → `task_success: 0.0`.

**Instruction-wording iteration, measured with a real agent** (`terminus-2` /
`openai/gpt-5.6-luna`, not oracle/nop). This is a live example of the turn-depth vs. task-design
tension: naming the exact bug's location makes a task pass but shallow; leaving it genuinely
findable is what actually produces both correctness and a real exploratory trajectory.

| `instruction.md` version | `task_success` | Turns | Tool calls |
|---|---|---|---|
| Original — "since that change went out" (implies the org-scoping rollout is already fully live) | 0.0 | 15 | 49 |
| Named the exact functions/files to fix | 1.0 | 6 | 16 |
| States the scope boundary (opt-in, callers must not change) without naming where the bugs live | 1.0 | 24 | 92 |

The middle version failed for a real reason worth keeping on record: the agent read "since that
change went out" as the migration being fully wired, and reasonably (but wrongly) finished
wiring `org_id` into `build_status`/`build_guide`'s call sites — which both left the actual
swapped-order bug unfixed and broke two pristine tests. The final version is what's committed.

## The second single-repo task: task-04

**Archived 2026-09-05** to `archive/old/tasks/task-04-schedule-page-boundary-duplication/`
(`docs/poc-scope.md` Step 2) — no longer part of the default `tasks/` sweep. Re-verification at the
`cdbf80b`/`24c21d4`/`09193c2` pins found the exact drift `docs/poc-scope.md`'s 2026-09-05 rescope
already anticipated: `harbor run -a oracle` scores `task_success: 0.0` with `TypeError:
channelSchedule is not a function` in both test cases. fast-world-tv's `6d09506` "v2 app shell"
rebuild replaced the old synchronous `channelSchedule`/`CHANNELS`-array shape this task's test
file calls directly with the new async, store-backed `channel-config-store` API — the function
this task's regression and fix both target no longer exists under that name/signature. Not
re-fixed, since the task is being retired; any FW-00N task touching fast-world-tv's schedule logic
needs to target the new async accessors from the start (see `docs/poc-scope.md` Step 2 template
note).

`tasks/task-04-schedule-page-boundary-duplication` is fast-world-tv's first task — single-repo,
same shape as task-01/02 but for the FAST viewer rather than ChannelForge or ssaiadserver.
fast-world-tv ships with **no test tooling at all** upstream (no vitest devDependency, no test
script), so this task adds `vitest` as an image-level devDependency in its own Dockerfile (not
touching `vendor/fastworldtv`'s own lockfile).

The bug: `channels.ts`'s guide/schedule builder decides which programmes fall inside a requested
`[from, to)` time window with `end > from && start < to`. The regression flips that to
`start <= to`, so a programme whose start lands exactly on a page boundary is included in *both*
the page ending at that boundary and the page starting at it — a real, plausible off-by-one (the
kind an engineer introduces "fixing" a perceived edge case without noticing the double-count it
creates across paginated requests).

One real build-environment issue surfaced and was fixed during validation: vitest's underlying
Vite instance auto-loads `postcss.config.mjs` from the project root during config resolution
(not lazily, and not gated by `test.css`), and that config's Tailwind v4 plugin isn't a shape
Vite's PostCSS loader accepts standalone — unrelated to the pure `src/lib` logic under test. Fixed
with an inline empty `css: { postcss: { plugins: [] } } }` in a task-level `vitest.config.ts`,
which bypasses the file search entirely.

Verified through real Harbor: `oracle` → `task_success: 1.0` (all four metrics), `nop` →
`task_success: 0.0`.

**Real-agent run** (`terminus-2`/`openai/gpt-5.6-luna`): `task_success: 1.0`, **8 turns / 23 tool
calls**. The instruction has no location pointers (same style as task-03's final version) — the
shallowness here isn't an instruction problem, it's structural: fast-world-tv's schedule logic
lives in one small file with a single call site, so there's little to explore. Confirms turn
depth and instruction quality are separate axes (see [[task_turn_depth_target]]): a task this
small needs a bug that spans more files/callers to reach 30+ turns, not a vaguer instruction.

## External world-readiness assessment

See `docs/world-blueprint-assessment.md` — a condensed, in-repo copy of an external review's
findings: what's real vs. gap per repo, what a genuine "world" layer needs that this repo doesn't
have yet (world-control service, virtualized time, deterministic reset, separate verifier images,
selective rebuilds), a candidate FW-001..010 task portfolio, verifier-design principles, and
release gates. Read before the POC-scope replan — several items in "Known gaps" below are also
called out there as release blockers, not just nice-to-haves.

## Known gaps — real, not yet closed

- **No `playout-worker` (or object storage / edge) in `world/docker-compose.yaml` yet.**
  `CF_DELIVERY_ORIGIN`'s HLS-origin packaging is implemented in
  `services/playout-worker/worker/run_channel.py`/`origin.py`, which writes segments/manifests
  to object storage (MinIO/S3 in ChannelForge's own dev compose) served by an edge (nginx in
  ChannelForge's own dev compose). None of that exists in this world yet — `CF_ORIGIN_BASE_URL`
  currently points at `main` itself as a placeholder, and nothing serves
  `delivery_master.m3u8` from there. **This means no schedule actually airs and no real SCTE
  cue markers exist to detect yet** — `ssai-data`'s origin fetch will just fail/retry against
  `main` until this is added. Standing up `playout-worker` + object storage + an edge route is
  the next real milestone before the end-to-end pipeline smoke test (docs/workflow.md) can pass
  for real, not a hand-simulation.
- `network_mode = "no-network"` is still not enforced (pre-existing gap, unaffected by adding
  two more services — see `docs/harbor-install.md`).
- fast-world-tv's guide/status proxying (see above) — deferred.
- Primary/backup redundancy flags — only enable per-task when a task specifically needs
  failover behavior.
