# The ecosystem: ChannelForge + ssaiadserver + fast-world-tv

This world grew from wrapping one service (ChannelForge) to wrapping the three repos that talk
to each other in production. This doc is the integration-contract reference so a task author
never has to re-derive it from source: what each repo actually expects from the others, the two
places those contracts didn't line up out of the box (and the small patches that bridge them),
and what's still missing before the pipeline is *live*, not just wired.

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

`PINNED_COMMIT_CHANNELFORGE` was bumped from task-01's original pin (`6ce2b1e`) to current HEAD
(`b46733b`, 52 commits later) — the original pin predates all of PRD 3.0 (FAST/SCTE/SSAI/EPG),
so none of that code existed in the old vendor snapshot. `task-01`'s regression patch was
re-verified to still apply and reverse byte-identically at the new pin (`app/services/rights.py`
is unchanged across those 52 commits), so this didn't require touching task-01.

## Integration contracts (as they actually exist upstream)

### ChannelForge → ssaiadserver

`apps/api/app/adapters/ssai_adserver.py`'s `SsaiAdServerAdapter` calls ssaiadserver's real routes:

```
POST /v1/ad-decision   {channel_id, opportunity_id, duration, [session_id], [seed]} -> {pod_id, ...}
GET  /v1/channels      (used as the preflight health check)
```

**Not wired into any live call path today** — `get_ssai_adapter`/the adapter is only constructed
in tests and the registry; no service or job in ChannelForge actually invokes it. It exists as a
tested contract for future §17 reconciliation-delivery-import wiring, not something this world's
pipeline currently exercises end to end. Treat "ChannelForge calls out to ssaiadserver" as **not
yet a real signal to verify a task against** — the live direction that *does* work is the next
one.

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

Pull-based, per ADR-9 (`channelforge/docs/adr/0009-pilot-distributor-target.md`):

| fast-world-tv side | ChannelForge side |
|---|---|
| per-channel `hlsUrl` | `{CF_ORIGIN_BASE_URL}/{output_id}/delivery_master.m3u8` (`apps/api/app/services/fast.py`) |
| `/api/fast/guide` (JSON EPG) | `GET /organizations/{org_id}/fast/guide` |
| `/api/fast/status` | `GET /organizations/{org_id}/fast/status` |

fast-world-tv's actual code today only implements the first row for real integration
(`FAST_HLS_101..105` env overrides in `src/lib/channels.ts`) — `/api/fast/guide` and
`/api/fast/status` are still fully local synthetic data, not proxying ChannelForge's real
endpoints. Wiring those up for real is a larger, separately-scoped follow-up (new fetch/cache
layer, error handling) — not required to prove the schedule→origin→SSAI→playback pipeline, and
deliberately deferred here.

## The two gaps that needed patching (and one that just needed enabling)

1. **Origin URL shape mismatch.** ChannelForge serves `{base}/{output_id}/delivery_master.m3u8`;
   ssaiadserver's `OriginClient` default is `{base}/{channel}/{variant}.m3u8`. Bridged by
   `world/patches/ssaiadserver-manifest-template.patch`, which adds an env-configurable
   `CHANNELFORGE_MANIFEST_PATH_TEMPLATE` (placeholders `{channel}`/`{variant}`) to `origin.ts`,
   applied at build time in `world/ssai/Dockerfile`. `world/docker-compose.yaml` sets it to
   `"{channel}/delivery_master.m3u8"` on `ssai-data`.
2. **No `SSAI_ADSERVER_BASE_URL` in ChannelForge.** `SsaiAdServerAdapter` needs a `base_url` +
   `transport` injected by its caller; nothing in `apps/api/app/config.py`/`registry.py` did
   that outside tests. Bridged by `world/patches/channelforge-ssai-base-url.patch`: adds
   `ssai_adserver_base_url` (env `CF_SSAI_ADSERVER_BASE_URL`) to `Settings`, plus
   `registry.get_configured_ssai_adapter()` wiring a real `httpx` transport (falls back to the
   fake adapter when unset). Applied at build time in `world/app/Dockerfile`. Since (per above)
   nothing calls `get_ssai_adapter` on any live path yet, this patch is forward-looking glue for
   whichever task first needs it, not something the current smoke test exercises.
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

## First task built on this: task-02

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
