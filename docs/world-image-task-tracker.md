# World image — task tracker

Execution breakdown of `docs/devops-single-image.md` (the Phase 1 single-image build spec) into
discrete, independently trackable tasks. Scope is the world image only — no task-idea/calibration/
benchmark work here (that's `docs/mvp-scope.md` Phases 2-5).

**This is a working tracker, not a spec.** `docs/devops-single-image.md` stays the source of truth
for *what* and *why*; this doc is *what order, how big, what's blocked on what*. Intended to move
to GitHub Issues later — each row is written to become one issue (title + size + deps), so keep
that shape rather than folding tasks together.

Sizes are rough (S ≈ hours, M ≈ 1-2 days, L ≈ 3+ days) — recalibrate after the first few land.
`Depends on` / `Blocks` reference task IDs in this doc, not the step numbers in the spec.

## Critical path

**T2 (Harbor command-override resolution) gates everything from T4 onward** — do it first,
regardless of where it falls in the spec's own step numbering. T9 (network egress), T10
(child-image-per-task prototype), T13 (DB seeding), T14 (integration stubs), and T15 (MinIO/CDN
assets) can all run in parallel with T5-T8 once T4 lands — T6.4/T7.3's playback proofs are the
only points where the media/fixture work (T13, T15) and the integration-stub work (T14.2 for the
SSAI VAST path) actually gate the streaming steps; nothing else in T13-T15 blocks T5-T8 directly.

## Tasks

### Step 1 — re-pin

- [x] **T1.1** — Re-run the upstream audit (`docs/devops-single-image.md` §2.1 fetch-diff) to
  confirm it hasn't gone stale. *Size: S. Blocks: T1.2.* — 2026-09-11: superseded by a policy
  change (pins now track each repo's `world` branch, not `main`) — see updated §2.
- [x] **T1.2** — Execute the coordinated three-repo re-pin (update the 3 `PINNED_COMMIT_*` files,
  regenerate `vendor/`). *Size: S. Depends on: T1.1. Blocks: T1.3, Step 3.* — 2026-09-11: merged
  `main` into `world` in all 3 source repos (2 conflicts hand-resolved in ssaiadserver, 1 in
  fast-world-tv), pushed, re-pointed `PINNED_COMMIT_*` to the new `world` HEADs (ChannelForge
  `bf56501`, ssaiadserver `8fccc2e`, fast-world-tv `52491a6`), regenerated `vendor/` clean.
- [x] **T1.3** — Re-check the T1-T10 idea catalogue (`docs/fast-world-bench.md`) against the
  re-pinned source — confirm none of those defects were fixed upstream. *Size: S. Depends on:
  T1.2.* — 2026-09-11: T1-T9's fixes are all present in current source (expected/healthy for
  `break.patch`-style tasks — still needs an actual patch-apply test before Phase 3 authoring,
  not just source inspection). T10 has no fix at all — genuinely unfixed, re-scope as a
  build-from-scratch feature task rather than a break-patch fix task. See `docs/fast-world-bench.md`
  §"Re-check against the re-pinned world-branch source".

### Step 2 — Harbor command-override resolution (gating — do first, real risk)

- [x] **T2.1** — Ask the Horizon harness owner whether `ventuno-world` runs through Harbor's
  `docker` environment provider or a different integration. *Size: S. Blocks: T2.3.* —
  2026-09-11: confirmed — it runs through Harbor's `docker` environment provider (the same
  compose-overlay mechanism this repo uses). The `sleep infinity` command-override risk
  documented in `docs/devops-single-image.md` §9 is real, not hypothetical.
- [x] **T2.2** — Build a throwaway supervisord-only image — no application stages, just the
  process-management skeleton. *Size: S. Blocks: T2.3.* — 2026-09-11: Ubuntu 24.04 + `supervisor`
  + 2 dummy heartbeat programs, built in scratch (not committed — genuinely throwaway).
- [x] **T2.3** — Run that throwaway image as a real Harbor `main` service (`harbor run -a oracle`/
  `-a nop`) and confirm supervisord survives (or doesn't) Harbor's `sleep infinity` command
  override. *Size: M. Depends on: T2.1, T2.2. Blocks: everything in T4+.* — 2026-09-11: **fails**
  with a bare `CMD supervisord ...` — verified via `harbor task start-env -i`, PID 1 was `sh -c
  "sleep infinity"`, supervisord never started. Confirms the risk from §9 is real.
- [x] **T2.4** — If T2.3 fails, implement and re-verify a fix (`ENTRYPOINT`-based or otherwise).
  *Size: M. Depends on: T2.3. Blocks: everything in T4+.* — 2026-09-11: fixed with an
  `ENTRYPOINT` script that ignores `"$@"` and unconditionally execs supervisord — re-verified via
  the same `harbor task start-env -i` path: supervisord is PID 1, both dummy programs `RUNNING`
  per `supervisorctl status`, Harbor's shell attachment still works. Pattern documented in
  `docs/devops-single-image.md` §9 for reuse in the real `Dockerfile` (§6). **Step 2 fully
  closed — Step 4+ is unblocked.**

### Step 3 — vendoring extension

- [x] **T3.1** — Extend `vendor-source.sh` to pull ChannelForge's `apps/web`. *Size: S. Depends on:
  T1.2. Blocks: T3.4.* — 2026-09-11: added `apps/web` to the ChannelForge `vendor_repo` call. No
  workspace deps on `packages/` — standalone Vite/React app.
- [x] **T3.2** — Extend vendoring/build to include ChannelForge's media + playout workers. *Size: M.
  Depends on: T1.2. Blocks: T3.4.* — 2026-09-11: added `services/media-worker` and
  `services/playout-worker` to the ChannelForge `vendor_repo` call. Both are Python packages that
  depend on `packages/media-engine` (already vendored) and, for playout-worker, `apps/api`
  (already vendored) — no other new paths needed.
- [x] **T3.3** — Extend vendoring/build to include SSAI's creative worker and remaining runtime
  packages. *Size: M. Depends on: T1.2. Blocks: T3.4.* — 2026-09-11: already satisfied by the
  existing `packages` wildcard copy (`packages/creative-worker` was already landing in `vendor/`)
  — no script change needed. Found a real build-stage note for Step 4: ssaiadserver's own
  `docker/Dockerfile` installs `ffmpeg`/`ffprobe` for the creative-worker — the real single-image
  `Dockerfile` needs the same system package.
- [x] **T3.4** — Verify each newly-vendored app builds independently, outside the monolith, before
  it's wired into the base. *Size: S. Depends on: T3.1, T3.2, T3.3. Blocks: Step 4.* — 2026-09-11:
  all 4 build clean at the new pins: `apps/web` (`npm install && npm run build`, standalone),
  `services/playout-worker` and `services/media-worker` (each built via its own real `Dockerfile`
  from the `channelforge` repo root, exactly as it will run in production), `packages/creative-worker`
  (`tsc --build` via the ssaiadserver npm workspace). All throwaway Docker images removed after
  verification; an incidental `package-lock.json` lockfile drift from `npm install` in ssaiadserver
  was reverted (not an intended change).

### Step 4 — final base + write boundary

- [x] **T4.1** — Design the write-boundary permission scheme (owners/users, which paths are
  protected — spec §5). *Size: M. Depends on: T2.4. Blocks: T4.2, everything in Step 10.* —
  2026-09-11: built (`worldagent` user, agent-writable trees mode 755, protected config mode
  750) but confirmed **not real enforcement today** — Harbor 0.22.0's docker provider has no
  `task.toml` field to default agent execs to a non-root user and no capability-dropping either
  (verified by reading `harbor/environments/base.py`/`docker.py` directly, then confirmed twice
  empirically: plain `docker exec` and a real `harbor task start-env -i` both show `whoami` →
  root, root can write `/etc/supervisor`; `--user worldagent` explicitly *does* enforce it
  correctly). Kept as structural/advisory per explicit direction — see
  `docs/devops-single-image.md` §5 for the full writeup. The real gap is now tracked there,
  same treatment as T9's no-network gap.
- [x] **T4.2** — Build the supervisor config for all ~14 programs, tiered by `priority=`. *Size: M.
  Depends on: T2.4, T4.1. Blocks: T4.5, Step 5.* — 2026-09-11: `world/image/supervisord.conf`,
  13/14 reach `RUNNING` (verified via both plain `docker run` and real `harbor task
  start-env -i`); the 14th (ChannelForge media worker) is a genuine upstream gap
  (`NotImplementedError` skeleton), left `autostart=false` rather than patched — see
  `docs/devops-single-image.md` §4.
- [x] **T4.3** — Build the nginx/HLS edge config. *Size: M. Depends on: T2.4. Blocks: Step 6.* —
  2026-09-11: `world/image/nginx.conf` — serves `apps/web/dist`, proxies `/api`+`/health` to
  `127.0.0.1:8000`, serves the playout worker's `CF_HLS_ROOT` under `/hls`. Verified `/health`
  proxies correctly.
- [x] **T4.4** — Integrate MinIO + the local integration stub, no sample data yet. *Size: M. Depends
  on: T2.4. Blocks: Step 6, 7.* — 2026-09-11: MinIO verified healthy
  (`/minio/health/live` → 200); local stub (`world/image/stub/stub_server.py`, pure-stdlib
  Python) verified — `/health` → `{"status": "ok"}`, a test POST logged deterministically to
  `/var/log/local-stub/requests.log` and acknowledged locally, no outbound calls of its own. No
  bucket contents yet, as scoped — that's Step 15.
- [x] **T4.5** — Implement per-service `wait-for-*.sh` readiness guards (spec §8) — supervisord's
  `priority` alone doesn't order readiness. *Size: M. Depends on: T4.2. Blocks: Step 5.* —
  2026-09-11: one generic `world/image/wait-for-tcp.sh <host> <port> [timeout]` rather than one
  script per dependency (every dependency here is "can I open a TCP connection"); each program's
  `command=` chains the specific calls it needs before `exec`ing the real process. **Step 4 fully
  closed — Step 5 (autostart + local endpoints) is unblocked.**

### Step 5 — autostart + local endpoints

- [ ] **T5.1** — Prove every process reaches `RUNNING` via `supervisorctl status`. *Size: S. Depends
  on: T4.5. Blocks: T5.2.*
- [ ] **T5.2** — Rewrite every production/public endpoint default to its local equivalent (spec §5's
  integration table). *Size: M. Depends on: T5.1. Blocks: Step 6, 7, 8.*

### Step 6 — ChannelForge fixture

- [ ] **T6.1** — Create synthetic programme media. *Size: M. Depends on: T4.3, T4.4. Blocks: T6.4.*
- [ ] **T6.2** — Adapt `scripts/seed_fixture.py` to bake at build time, with storage rows pointing at
  real local MinIO objects. *Size: M. Depends on: T5.2, T6.1. Blocks: T6.4.*
- [ ] **T6.3** — Decide and implement the time/reset-determinism rule (fixed epoch vs. deterministic
  reset op). *Size: M. Blocks: T6.2.*
- [ ] **T6.4** — Prove raw HLS playback through host port `18080`. *Size: S. Depends on: T6.2, T6.3,
  T15.2. Blocks: Step 7.*

### Step 7 — SSAI fixture

- [ ] **T7.1** — Create synthetic ad/slate media, run it through the real creative-worker prep path.
  *Size: M. Depends on: T3.3, T6.4. Blocks: T7.3.*
- [ ] **T7.2** — Bake the SSAI seed (persistence package's seed command); rewrite calendar dates and
  origin hostnames. *Size: M. Depends on: T5.2, T7.1. Blocks: T7.3.*
- [ ] **T7.3** — Prove stitched HLS playback through `14000`/`14010`. *Size: S. Depends on: T7.2,
  T15.3, T14.2. Blocks: Step 8.*

### Step 8 — FAST World

- [ ] **T8.1** — Wire FAST World to local EPG/origin/SSAI endpoints, no Upstash/Vercel production
  fallback. *Size: M. Depends on: T7.3. Blocks: T8.2.*
- [ ] **T8.2** — Prove browser playback through `13000`. *Size: S. Depends on: T8.1. Blocks: Step 11.*

### Step 9 — network egress (scoped separately, per acceptance gate item 14)

- [ ] **T9.1** — Decide egress-control sidecar vs. an environment provider with native `no-network`
  support. *Size: M. Blocks: T9.2.*
- [ ] **T9.2** — Implement and validate the chosen fix; confirm `harbor run` with real network
  isolation works. *Size: M. Depends on: T9.1. Blocks: T9.3, Step 11.*
- [ ] **T9.3** — DNS/HTTP capture of a full smoke test proving zero public-hostname requests. *Size:
  S. Depends on: T9.2. Blocks: Step 11.*

### Step 10 — child-image-per-task prototype

- [ ] **T10.1** — Pick one representative Phase 1 task idea from the T1-T10 catalogue (needs a
  rubric-passed idea — see `docs/mvp-scope.md` Phase 3, out of scope for this tracker). *Size: S.
  Depends on: T4.1. Blocks: T10.2.*
- [ ] **T10.2** — Build that task's child image `FROM` the base, applying `setup/regression.patch`.
  *Size: M. Depends on: T10.1. Blocks: T10.3.*
- [ ] **T10.3** — Determine which of the spec's ten build stages (§6) survive the patch unchanged vs.
  must re-run; record the answer there. *Size: S. Depends on: T10.2. Blocks: T10.4.*
- [ ] **T10.4** — Validate `oracle`/`nop` against the prototype task. *Size: S. Depends on: T10.3.
  Blocks: Step 11.*

### Step 13 — DB seeding (cross-cutting: ChannelForge + SSAI)

- [ ] **T13.1** — Apply ChannelForge's Alembic migrations as a baked build stage (spec §6 stage 7).
  *Size: S. Depends on: T4.2. Blocks: T6.2.*
- [ ] **T13.2** — Apply SSAI's migrations as a baked build stage (spec §6 stage 8). *Size: S. Depends
  on: T4.2. Blocks: T7.2.*
- [ ] **T13.3** — Verify two fresh containers from the same image expose byte-identical seeded state
  in both databases, with no external seed step executed at first boot (acceptance gate #7). *Size:
  S. Depends on: T6.2, T7.2.*
- [ ] **T13.4** — Confirm the baked fixture contains no customer-derived data or PII — remove or
  replace any titles still claimed as production-derived (spec §7). *Size: S. Depends on: T6.2.*

### Step 14 — External integration stubs / local replacements

Every capability in spec §5's integration table needs an explicit disposition — stubbed, disabled,
or redirected — not left to fall out of other steps incidentally.

- [ ] **T14.1** — Build the local integration stub service itself: health endpoint, deterministic
  request logging, refuses to proxy unknown URLs, on port 9080 (spec §5). *Size: M. Depends on:
  T4.4. Blocks: T14.2, T14.3.*
- [ ] **T14.2** — Point ssaiadserver's VAST tag/wrapper retrieval at a deterministic local VAST stub;
  reject unknown hosts. *Size: S. Depends on: T14.1.*
- [ ] **T14.3** — Point ssaiadserver's impression/tracking beacons and any generic webhook/Slack
  calls at the local beacon/webhook collector only. *Size: S. Depends on: T14.1.*
- [ ] **T14.4** — Disable (or confirm blank credentials for) ChannelForge's YouTube/Google OAuth,
  Google Drive/Dropbox import, SFTP import/export, RTMP/RTMPS/SRT push destinations, and SMTP
  alerts — each must stay dormant with no destination configured. *Size: M. Depends on: T5.2.*
- [ ] **T14.5** — Confirm FAST World's Upstash/Vercel KV integration uses its supported in-memory (or
  local adapter) fallback, never a production default, for every missing environment variable.
  *Size: S. Depends on: T8.1.*
- [ ] **T14.6** — Walk spec §5's full integration table line by line against the built image; any
  newly found live integration is release-blocking until stubbed, redirected, or disabled. *Size: S.
  Depends on: T14.1-T14.5. Blocks: T9.3, Step 11 (acceptance gate #15).*

### Step 15 — MinIO CDN + seeded static assets (media, images, other static content)

- [ ] **T15.1** — Stand up MinIO with separate ChannelForge and SSAI buckets. *Size: S. Depends on:
  T4.4. Blocks: T15.2, T15.3, T15.4.*
- [ ] **T15.2** — Load normalized programme media into ChannelForge's MinIO bucket, with keys
  matching the seeded DB rows exactly. *Size: M. Depends on: T15.1, T6.1, T6.2. Blocks: T6.4.*
- [ ] **T15.3** — Load prepared ad/slate HLS objects into SSAI's MinIO bucket, with keys matching the
  seeded SSAI rows exactly. *Size: M. Depends on: T15.1, T7.1, T7.2. Blocks: T7.3.*
- [ ] **T15.4** — Create and seed deterministic poster/artwork/other browser-fetched image assets for
  FAST World — no remote image URL anywhere in the served pages (spec §5). *Size: M. Depends on:
  T15.1. Blocks: T8.1.*
- [ ] **T15.5** — Wire nginx/the CDN edge to serve MinIO-backed static assets locally (poster/
  artwork and any other browser-fetched static content); confirm no fallback to a remote host.
  *Size: S. Depends on: T15.4, T4.3.*
- [ ] **T15.6** — Verify every MinIO object referenced by a seeded DB row actually exists — no
  dangling storage references (acceptance gate #6). *Size: S. Depends on: T15.2, T15.3, T15.4.
  Blocks: Step 11.*

### Step 11 — acceptance gate

- [ ] **T11.1** — Run all 18 acceptance-gate checks (spec §11) end to end. *Size: L. Depends on:
  Steps 5-10, 13-15 complete. Blocks: T11.2.*
- [ ] **T11.2** — Fix any failures found and re-run until all 18 pass. *Size: depends on findings.
  Depends on: T11.1. Blocks: Step 12.*

### Step 12 — publication

- [ ] **T12.1** — Decide Google Artifact Registry project, repo, retention, and external-team access
  policy. *Size: M. Blocks: T12.2.*
- [ ] **T12.2** — Cut the first tagged release with its release manifest (source commits + image
  digest). *Size: S. Depends on: T11.2, T12.1.*
