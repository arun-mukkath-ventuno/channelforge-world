# FAST World MVP — scope document

Living scope doc for the MVP phase that follows the POC (`docs/poc-scope.md`). Where the POC
proved the harness end-to-end on 5 tasks × up to 4 models, the MVP scopes what it takes to ship a
real 10-task cross-LLM benchmark: a distributable environment, a repeatable process for turning
task ideas into calibrated Harbor tasks, and a final benchmark run with saved results/metrics.

Five phases, in dependency order — each phase's output is a real input to the next one, not a
parallel workstream:

1. Docker setup (distributable environment)
2. Task run environment (where Harbor actually executes)
3. Task ideas (candidate list + a rubric to filter it)
4. Task creation + 10-trial calibration (idea → built, calibrated Harbor task)
5. Final benchmark (10 tasks × 5 trials × the model roster, results saved)

## 1. Docker setup

**Decision (per team direction): single distributable image**, modeled on `ventuno-world:0.2.0`'s
*packaging pattern* — not its code or architecture (that product is PHP/Apache/MySQL/Solr/
RabbitMQ; this one is Python/Node/Next.js/React and shares nothing tech-stack-wise). What's being
reused is the pattern: supervisord as PID 1, tiered `priority=` startup with `wait-for-*.sh`
gating, all inter-service traffic rewired to `127.0.0.1:<port>` (no container DNS names), optional
`[group:]` blocks.

**Current reality vs. the plan** — this is not yet built:
- **Today**: 4 separate per-service Dockerfiles (`world/app`, `world/db`, `world/fastweb`,
  `world/ssai`) + a 9-service dev/CI `docker-compose.yaml` (`postgres`, `redis`, `main` — must be
  named exactly `main`, Harbor's `MAIN_SERVICE_NAME` constant — `scheduler`, `ssai-postgres`,
  `ssai-redis`, `ssai-control`, `ssai-data`, `fast-web`), all wired via compose DNS names. This is
  explicitly documented as "the right shape for local development," not the distributable shape.
- **The plan** (`docs/devops-single-image.md`): a full multi-stage `world/image/Dockerfile` build —
  port map, supervisord config, versioning/tagging scheme, a pre-publish validation gate
  (`supervisorctl status` all RUNNING, every task's `harbor run -a oracle`/`nop` still passes,
  `docker history`/`dive` to confirm no `tests/`/`solution/` leaked into a layer), rollback policy.
  Already fully specced, not yet executed. Expect the built image to be **large** (doc's own
  estimate: comparable to `ventuno-world:0.2.0`'s 8.9GB) — a real infra cost to plan around, not a
  surprise to discover later.
- Baking sample/fixture data into the image (extending the existing `bake-fixture-db.sh` /
  `scripts/seed_fixture.py` pattern as a `COPY --from=` build stage) is explicitly future work
  inside that same doc — sequence it after the base single-image build works, not before.

**Known tension, noted not resolved here**: `docs/world-blueprint-assessment.md` (external review)
recommends the opposite — "one versioned world release = several service images + Compose
topology, not one monolithic image." The team has already decided single-image for this MVP; this
is flagged so the tradeoff is visible, not silently dropped. Revisit if the single image proves
unwieldy to build/version in practice.

## 2. Task run environment

A Linux server with SSH access, running:

- **Docker support**: Docker Engine + Compose. Only Harbor's local Docker provider (`-e docker`)
  has been validated in this repo — other providers (daytona/e2b/modal/runloop/gke) are untested
  and out of scope for the MVP.
- **Harbor**: isolated `.venv`, `pip install harbor` (0.22.0 validated, `schema_version "1.4"`).
  Core command shape used throughout: `harbor run -p <task-dir> -a <agent> [-m <model>] -e docker
  -y --jobs-dir <dir> [--env-file .env]`.
- **Agent**: `terminus-2` is the validated reference agent (every real run in this repo so far).
  `codex` (needs `OPENAI_API_KEY`) and `claude-code` (needs `ANTHROPIC_API_KEY`) are available but
  not yet run — not required for the MVP unless the benchmark wants agent-harness variance as a
  dimension, which is out of scope here (model variance only).
- **World**: the single distributable image from Phase 1 once it exists; until then, the current
  multi-container `world/docker-compose.yaml` stack is what tasks actually build on.
- **LLM access via API** — real operational findings from today's pilot, worth carrying forward
  as run-book knowledge rather than rediscovering per session:
  - `OPENROUTER_API_KEY` alone reaches most major labs' models with one key — the pragmatic
    default for open-weight/multi-lab coverage (`docs/mvp-leaderboard-roster.md`).
  - **Always verify a topup actually landed** before trusting a paid model run: `GET
    https://openrouter.ai/api/v1/credits` and `.../api/v1/key` (`total_credits`, `is_free_tier`) —
    a topup that hasn't propagated yet produces confusing, misleading-looking errors (worst-case
    affordability prechecks, in-flight-budget exhaustion) that look like model or task problems
    but are actually billing-propagation delay.
  - **Free-tier model slugs can die mid-sweep**, not just rate-limit — confirm via `GET
    /api/v1/models` that a `:free` slug still exists before re-running into a dead one.
  - Some models need explicit `terminus-2` kwargs to run cleanly: e.g. `openai/gpt-6-astra`
    rejects any non-default `temperature` (`--ak temperature=1`); OpenRouter paid models often need
    an explicit `max_tokens` ceiling to avoid the affordability precheck (`--ak
    'llm_kwargs={"max_tokens": 8000}'` — note `--ak max_tokens=...` alone silently no-ops, since
    `max_tokens` isn't a direct `Terminus2.__init__` kwarg).
  - Google AI Studio's free tier has its own separate per-minute token quota (`GEMINI_API_KEY`,
    distinct from OpenRouter's request-count-based limits) — worth routing through
    `openrouter/google/<model>` instead if that quota becomes a bottleneck for repeated runs.
- **Server spec**: no real load-testing done yet, so treat this as a starting estimate to revise
  once the single image exists and concurrent-trial load is actually measured. Given the expected
  ~9GB image plus room for Postgres/Redis (×2) plus concurrent Harbor trial containers, a
  reasonable starting point is **8 vCPU / 32GB RAM / 200GB SSD** — revisit after Phase 1 lands.
- **Optional: a UI to run/monitor trials, tasks, results, metrics.** Nothing like this exists in
  the repo today beyond Harbor's own built-in `harbor view <jobs-dir>` (a local web viewer over
  trajectories/transcripts/rewards). Treat as explicitly optional/deferred scope for the MVP —
  `harbor view` plus the `scripts/summarize-runs.py` CSV/markdown output (Phase 5) is enough to
  ship the benchmark; a dedicated dashboard is a real but separate later investment.

## 3. Task ideas

`docs/fast-world-bench.md` already proposes a **10-idea catalogue** (T1–T10:
`ssai-live-edge-avail-completion`, `ssai-live-edge-holdback`, `ssai-loop-ads-to-fill`,
`cf-scte35-dual-markers`, `cf-breakid-threading-reconciliation`, `cf-vast-macro-validation`,
`fwtv-beacons-never-arrive`, `fwtv-scrubber-origin-timeline`, `ssai-caddy-preflight-ordering`,
`cf-epg-break-extended-timings`) — **ideas, not built tasks**; none of these correspond to
directories under `tasks/` today. This is the starting backlog for Phase 3/4, not a finished task
set.

**Open question, not resolved here**: the POC's existing 5 tasks (`tasks/task-05-*` ..
`tasks/task-09-*`) already exist, are hardened, and have real trajectory data (`docs/ecosystem.md`,
`docs/model-providers.md`). Does the MVP's "10 tasks" reuse those 5 (re-scored against the rubric
below, since they predate it) and add 5 new ones from the T1–T10 catalogue, or does it start fresh?
Recommend reusing task-05..09 where they pass the rubric retroactively — re-running the idea rubric
against an already-built task is cheap compared to designing five brand-new ones from scratch —
but this needs an explicit decision before Phase 4 starts, not an assumption baked in here.

### Task-idea rubric

Distilled from `horizon`'s two rubric layers (`docs-for-agent/task-idea-evaluation-workflow.md`'s
13-criterion `/65` idea rubric, and `workflow/task-idea-to-task-instruction-workflow/decision-
model.md`'s more mature 17-criterion `/85` version + hard gates), genericized off Ventuno/Horizon-
specific terminology. Lighter than porting either wholesale; keeps the parts that are product-
agnostic and drops the parts that are tool-specific (Argus flags, Bespoke review, Horizon CLI).

**Score each candidate idea 1 (absent) – 5 (exemplary) on:**

| Criterion | What it's asking |
|---|---|
| Realism | Is this a genuine defect/requirement shape, not an invented puzzle? |
| Discovery depth | Does solving it require tracing across multiple files/services, not one obvious spot? |
| Shortcut resistance | Would a noop, a hardcoded constant, or a schema-only hack score 0 against the grader? |
| Domain-knowledge ceiling | Could an experienced engineer with *zero* knowledge of this codebase solve it from general knowledge alone? (If yes → drop or revise; genuine SQL-parameterization/idempotency-guard/null-check-shaped fixes always score too high here.) |
| Grader strength | Is it verifiable programmatically (HTTP/DB/CLI/test), not something needing an LLM judge for anything that's otherwise checkable? |
| Buildability | Does the infra it needs already exist in the vendored repos / current world, buildable without new upstream features? |
| Bounded session | Solvable inside one Harbor agent timeout window — not a multi-session, long-horizon task? |
| Novelty | Not a near-duplicate of an existing `tasks/` or `archive/old/tasks/` task (same observable problem + same root cause + same fix shape + same grader discriminator = reject as duplicate)? |

**Threshold to proceed to build: ≥ 28/40.** (Deliberately lighter than horizon's 52/65 — this MVP
is calibrating its own bar as it goes; tighten once a few tasks have gone through Phase 4 and the
threshold's real predictive value is known.)

**Pattern check (pick at least one)** — the 6 structural task-design patterns from horizon's
`docs-internal/task-design-patterns.md`, product-agnostic difficulty *mechanisms*: Find-it-Easy-
Fix-it-Hard, Plausible Trap, Invisible Constraint, Necessary-But-Not-Sufficient, Specification
Reader, Iceberg. An idea that doesn't map to any of these is probably too flat (single obvious fix,
no real discriminator between models).

**Hard gates (binary, all must hold before building)** — adapted from horizon's `G1-G12` checklist
and `docs/world-blueprint-assessment.md`'s anti-gaming checks:
- No leaked bug markers in the eventual instruction text ("bug", "TODO", "FIXME", or anything that
  points at the fix).
- Grader/hidden test data isolated from agent-writable paths (this repo's existing write-boundary
  convention — see `docs/PROJECT-SUMMARY.md`'s guardrail: agent may only touch application source,
  never Dockerfiles/compose/task infra).
- Deterministic reset (same broken state every run — no flaky verifier, no un-seeded randomness).
- No PII/credentials anywhere in fixtures.
- Instructions never name the exact file/line — navigation signal only (service/port names are
  fine, implementation hints are not).

## 4. Task creation and 10-trial calibration

Once an idea clears the Phase 3 rubric, build it following the real Harbor layout already in use
(`tasks/task-05-*` .. `task-09-*` as the concrete template): `task.toml` (schema_version "1.4"),
`instruction.md`, `environment/{Dockerfile,docker-compose.yaml}`, `solution/solve.sh`,
`tests/test.sh`, optionally `setup/regression.patch` if the regression is applied as a patch rather
than baked into the Dockerfile (task-08's pattern).

**Build-quality bar before calibration starts** — same checks every task-05..09 already went
through, made explicit here as a checklist:
1. `harbor run -a nop` → `task_success: 0.0` (broken state is genuinely broken).
2. `harbor run -a oracle` → `task_success: 1.0`, **run 3×** (horizon's reproducibility check —
   catches flaky verifiers before they cost calibration trials).
3. At least one adversarial probe (a plausible *wrong* fix — partial, hardcoded, wrong boundary
   condition) confirmed to score 0. Today's pilot surfaced two real examples worth using as
   worked references for what this catches: `deepseek-v4-flash-0731`'s task-05 near-miss (correct
   bug diagnosis, incomplete fix — still returned the first break's id for the second break in a
   zero-gap case) and `gemini-3.5-flash-lite`'s identical failure mode on the same task, both
   caught cleanly by the existing hidden randomized-run test.

**10-trial calibration**: run the built task against **one pinned mid-level model** — `openai/
gpt-5.6-luna`, already the repo's proven, deeply-characterized reference point
(`docs/mvp-leaderboard-roster.md` names it exactly this) — for **10 trials**
(`harbor run -p tasks/<task> -a terminus-2 -m openai/gpt-5.6-luna -k 10 -n <concurrency> -e docker
-y --env-file .env --jobs-dir <dir>`).

**Target band: `task_success` between 0.1 and 0.6.** (Deliberately wider than horizon's 0.2-0.4 or
`docs/fast-world-bench.md`'s own draft 0.2-0.6 — an intentional MVP-stage looseness, not an
oversight; tighten once the benchmark has enough real data to know where the useful discriminating
band actually sits for this task set.)

- **Below 0.1 (too hard)** — diagnose before touching difficulty, in this order (horizon's
  remediation-loop order, worth keeping as-is): (1) is the verifier itself flaky/wrong? (2) is the
  instruction underspecified — read the failed trajectories directly, same method used for every
  real diagnosis in `docs/ecosystem.md` and today's pilot session, never assume "model limitation"
  without reading the actual trajectory. (3) only once both are ruled out, soften: add scaffolding,
  clarify the spec, or split the task.
- **Above 0.6 (too easy)** — harden: remove hints, widen the affected surface, tighten the
  invariant the grader checks, add an adversarial input case.
- **Not converging after 1-2 hardening/softening passes** — abandon and replace with the next
  rubric-passed idea from the Phase 3 backlog. Don't sink more than 2 rounds into a single task.

**Run-quality rubric (post-run, separate from the Phase 3 idea rubric)** — evaluates the actual
10-trial data for reward-hacking or misleading agent behavior, not just the pass rate:
- Adversarial-probe log: did any trial's *passing* run actually take a shortcut the grader should
  have caught (noop, hardcoded constant, schema-only stub)? If so, that's a grader gap, not a
  legitimate pass — harden the grader, not the task difficulty.
- Fix-precision check: for trials that scored 0, did the agent diagnose the right root cause but
  ship an incomplete fix (the deepseek/gemini pattern above), or did it miss the bug entirely?
  Different signal — the former is real partial credit worth noting in the write-up even though
  `task_success` doesn't capture it; the latter is a genuine capability gap.
- **Known gap to close, not yet solved anywhere in this repo**: `docs/PROJECT-SUMMARY.md` records
  that `policy_compliance`/`side_effect_safety` are hardcoded to `1.0` in some early tasks — "no
  automated check yet for did the agent touch anything it shouldn't have." Any task built for this
  MVP should have a real check here, not a hardcoded pass, before it counts as calibrated.

## 5. Final benchmark

Once 10 tasks are built and calibrated (Phase 4), run the full benchmark: **10 tasks × 5 trials
each**, across the model roster. Same native Harbor sweep mechanic already proven in the POC pilot
— one `harbor run -p tasks/ -a terminus-2 -m <model> -k 5 -n <concurrency> -e docker -y --env-file
.env --jobs-dir <dir>` invocation per model (or per-attempt invocations if per-trial naming
granularity matters, per the pilot's `scripts/run-pilot.sh` precedent).

**Model roster**: build on `docs/mvp-leaderboard-roster.md`'s tiered proposal (frontier ×2,
frontier-other-labs ×2, mid/pinned-reference ×2, open-weight ×3, weak-control ×1) rather than
inventing a new one — it already reasons about cross-lab coverage, a stable pinned reference
re-run every release, and a deliberately weak control to confirm the benchmark discriminates at
all. Confirm each model actually works (smoke-test first, same discipline as today's pilot session
— several models needed provider-specific fixes before a clean run: `gpt-6-astra`'s temperature
constraint, OpenRouter paid models' `max_tokens` cap, dead free-tier slugs) before committing its
share of the 50-trial run.

**Budget math**: 10 tasks × 5 trials × N models = 50N trials. At N=10 (the full proposed roster)
that's 500 trials — a real cost/time budget, not a rounding error; pin exact dated model snapshots
and decide a refresh cadence before committing, since labs ship monthly.

**Results and metrics saved**:
- Build `scripts/summarize-runs.py` (planned in the POC's pilot phase, not yet built) — walks a
  `--jobs-dir` tree, pulls `task_success` + the other reward dimensions from `verifier/reward.json`,
  turns/tool-calls from `agent/trajectory.json`, wall time and exceptions from `result.json`, token
  counts from each episode's `debug.json`. Emits one row per (task, model, attempt) as CSV, plus a
  markdown summary table.
- Persist raw trial data the same way today's pilot committed it: `jobs/<benchmark-run-date>/`
  checked into git, pruned of terminal recordings (`.cast`/`.pane`) and per-episode `debug.json`
  before committing (today's pilot: 359MB → 21MB after pruning) — keep the reward/trajectory JSON
  that actually backs the analysis, drop the bulk that doesn't.
- Write up findings the same way `docs/ecosystem.md` and today's pilot session did: read a sample
  of actual trajectories per (task, model) cell, not just the aggregate numbers — today's pilot
  data already previews what this looks like in practice (e.g. `task-08` showing a 47-turn mean
  with a 255-turn outlier that still scored `task_success: 1.0`, vs. OpenAI models solving the same
  task in 7-13 turns every time — a model-efficiency signal aggregate scores alone would miss; or
  `gemini-3.5-flash-lite`'s clean, reproducible split — 0/N on two tasks, N/N on three others,
  not noisy variance).

## Critical files

- `docs/devops-single-image.md` — the single-image build spec (Phase 1), not yet executed.
- `world/image/Dockerfile` (new, Phase 1) — the actual single-image build target.
- `docs/model-providers.md` — provider/model operational findings (Phase 2), keep appending real
  findings here the way today's session did.
- `docs/fast-world-bench.md` — the T1-T10 idea catalogue (Phase 3 backlog).
- This doc's task-idea rubric (Phase 3) — apply to both the T1-T10 catalogue and (per the open
  question above) retroactively to `tasks/task-05-*`..`task-09-*`.
- `tasks/task-05-*` .. `task-09-*` — the real Harbor task layout template for Phase 4.
- New: `scripts/summarize-runs.py` (Phase 5, planned since the POC pilot, not yet built).
- `docs/mvp-leaderboard-roster.md` — model roster starting point for Phase 5.
- New: a final benchmark write-up doc (exact name/location TBD, likely alongside
  `docs/pilot-results-*.md` if that pattern is already in use by the time this phase runs).

## Verification

- Phase 1: single image builds clean, `supervisorctl status` all RUNNING, every existing task's
  `oracle`/`nop` still passes against it, `docker history`/`dive` confirms no `tests/`/`solution/`
  leaked into a layer.
- Phase 2: a fresh server following this doc's spec can run `harbor run -a oracle` on an existing
  task end-to-end with no manual intervention beyond the documented setup steps.
- Phase 3: every candidate that proceeds to Phase 4 has a filled-out rubric score (≥28/40), at
  least one matched design pattern, and all 5 hard gates checked.
- Phase 4: each of the 10 tasks has its `nop`→0/`oracle`→1×3/adversarial-probe→0 checklist done,
  and a 10-trial `gpt-5.6-luna` run landing in the 0.1-0.6 band (or an explicit, documented
  decision to abandon and replace it).
- Phase 5: the final 50N-trial summary table shows real `task_success` variance across both tasks
  and models (not degenerate all-0/all-1 for any cell, which would flag a broken task or model
  hookup rather than real signal) — same sanity bar the POC pilot itself was built to satisfy,
  now applied at full benchmark scale.

## Status

- [ ] Phase 1 — Docker setup (single image) — not started (spec exists in `docs/devops-single-
      image.md`, build not executed)
- [ ] Phase 2 — Task run environment — partially real (Harbor/agent/LLM-access all validated in
      the POC; server spec is an untested estimate; UI explicitly deferred)
- [ ] Phase 3 — Task ideas + rubric — idea catalogue exists (`docs/fast-world-bench.md`), rubric
      defined in this doc, not yet applied to any candidate
- [ ] Phase 4 — Task creation + calibration — not started (open question on task-05..09 reuse
      needs deciding first)
- [ ] Phase 5 — Final benchmark — not started (blocked on Phase 4)
