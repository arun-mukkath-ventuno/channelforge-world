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
regardless of where it falls in the spec's own step numbering. T9 (network egress) and T10
(child-image-per-task prototype) can run in parallel with T5-T8 once T4 lands, rather than waiting
in line behind T8.

## Tasks

### Step 1 — re-pin

- [ ] **T1.1** — Re-run the upstream audit (`docs/devops-single-image.md` §2.1 fetch-diff) to
  confirm it hasn't gone stale. *Size: S. Blocks: T1.2.*
- [ ] **T1.2** — Execute the coordinated three-repo re-pin (update the 3 `PINNED_COMMIT_*` files,
  regenerate `vendor/`). *Size: S. Depends on: T1.1. Blocks: T1.3, Step 3.*
- [ ] **T1.3** — Re-check the T1-T10 idea catalogue (`docs/fast-world-bench.md`) against the
  re-pinned source — confirm none of those defects were fixed upstream. *Size: S. Depends on: T1.2.*

### Step 2 — Harbor command-override resolution (gating — do first, real risk)

- [ ] **T2.1** — Ask the Horizon harness owner whether `ventuno-world` runs through Harbor's
  `docker` environment provider or a different integration. *Size: S. Blocks: T2.3.*
- [ ] **T2.2** — Build a throwaway supervisord-only image — no application stages, just the
  process-management skeleton. *Size: S. Blocks: T2.3.*
- [ ] **T2.3** — Run that throwaway image as a real Harbor `main` service (`harbor run -a oracle`/
  `-a nop`) and confirm supervisord survives (or doesn't) Harbor's `sleep infinity` command
  override. *Size: M. Depends on: T2.1, T2.2. Blocks: everything in T4+.*
- [ ] **T2.4** — If T2.3 fails, implement and re-verify a fix (`ENTRYPOINT`-based or otherwise).
  *Size: M. Depends on: T2.3. Blocks: everything in T4+.*

### Step 3 — vendoring extension

- [ ] **T3.1** — Extend `vendor-source.sh` to pull ChannelForge's `apps/web`. *Size: S. Depends on:
  T1.2. Blocks: T3.4.*
- [ ] **T3.2** — Extend vendoring/build to include ChannelForge's media + playout workers. *Size: M.
  Depends on: T1.2. Blocks: T3.4.*
- [ ] **T3.3** — Extend vendoring/build to include SSAI's creative worker and remaining runtime
  packages. *Size: M. Depends on: T1.2. Blocks: T3.4.*
- [ ] **T3.4** — Verify each newly-vendored app builds independently, outside the monolith, before
  it's wired into the base. *Size: S. Depends on: T3.1, T3.2, T3.3. Blocks: Step 4.*

### Step 4 — final base + write boundary

- [ ] **T4.1** — Design the write-boundary permission scheme (owners/users, which paths are
  protected — spec §5). *Size: M. Depends on: T2.4. Blocks: T4.2, everything in Step 10.*
- [ ] **T4.2** — Build the supervisor config for all ~14 programs, tiered by `priority=`. *Size: M.
  Depends on: T2.4, T4.1. Blocks: T4.5, Step 5.*
- [ ] **T4.3** — Build the nginx/HLS edge config. *Size: M. Depends on: T2.4. Blocks: Step 6.*
- [ ] **T4.4** — Integrate MinIO + the local integration stub, no sample data yet. *Size: M. Depends
  on: T2.4. Blocks: Step 6, 7.*
- [ ] **T4.5** — Implement per-service `wait-for-*.sh` readiness guards (spec §8) — supervisord's
  `priority` alone doesn't order readiness. *Size: M. Depends on: T4.2. Blocks: Step 5.*

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
- [ ] **T6.4** — Prove raw HLS playback through host port `18080`. *Size: S. Depends on: T6.2, T6.3.
  Blocks: Step 7.*

### Step 7 — SSAI fixture

- [ ] **T7.1** — Create synthetic ad/slate media, run it through the real creative-worker prep path.
  *Size: M. Depends on: T3.3, T6.4. Blocks: T7.3.*
- [ ] **T7.2** — Bake the SSAI seed (persistence package's seed command); rewrite calendar dates and
  origin hostnames. *Size: M. Depends on: T5.2, T7.1. Blocks: T7.3.*
- [ ] **T7.3** — Prove stitched HLS playback through `14000`/`14010`. *Size: S. Depends on: T7.2.
  Blocks: Step 8.*

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

### Step 11 — acceptance gate

- [ ] **T11.1** — Run all 18 acceptance-gate checks (spec §11) end to end. *Size: L. Depends on:
  Steps 5-10 complete. Blocks: T11.2.*
- [ ] **T11.2** — Fix any failures found and re-run until all 18 pass. *Size: depends on findings.
  Depends on: T11.1. Blocks: Step 12.*

### Step 12 — publication

- [ ] **T12.1** — Decide Google Artifact Registry project, repo, retention, and external-team access
  policy. *Size: M. Blocks: T12.2.*
- [ ] **T12.2** — Cut the first tagged release with its release manifest (source commits + image
  digest). *Size: S. Depends on: T11.2, T12.1.*
