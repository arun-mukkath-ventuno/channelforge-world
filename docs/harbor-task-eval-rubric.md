# Harbor task evaluation rubric

Evaluate a **built** Harbor task — after `docs/task-idea-rubric.md`'s idea gate has passed and the
task exists under `tasks/<name>/` — before it's added to a calibration run or the final benchmark.
The idea rubric rates the concept; this one rates whether the delivered artifact actually realizes
that concept and can't be gamed. Score every task through this before it counts as calibrated
(`docs/mvp-scope.md` Phase 4).

**Why this is a separate gate.** `horizon`'s own build data is the concrete warning: strong ideas
(34–53/65) shipped as builds that lost 16–18 points, almost always to one of two things — a planted
solution marker at the exact edit site, or an untested requirement the grader never actually
checked. A build can silently destroy everything the idea promised. Run every task through this
guide before it's trusted.

Sources this is distilled from: `horizon`'s `docs-for-agent/task-scoring-rubric.md` (the fill-in
form) and `docs-internal/task-build-quality-guide.md` (the scoring guidance behind it) — both
genericized off Ventuno/PHP-specific tooling and re-grounded in this repo's own two hardening
histories (`tasks/task-05-*`, `tasks/task-09-*`, `docs/ecosystem.md`) and its own confirmed grader
gap (`docs/pilot-dashboard-2026-09-07.html`'s findings panel). See "External grounding" for why
Area 4 below is weighted heaviest.

## Part 0 — Hard gates (binary; any failure = not calibration-ready)

Not scored — a single failure blocks the task regardless of its rubric total. Fix the gate, then
score.

| # | Gate | Pass condition |
|---|---|---|
| G1 | **Broken state fails** | From a clean reset: apply the regression, run the grader, `task_success` must be `0`. |
| G2 | **Oracle passes** | From the same clean broken state: run `solution/solve.sh`, run the grader, `task_success` must be `1`. Repeat at least **3×** (this repo's existing convention for task-05/09, tighter than horizon's 2×) — intermittent passes are not acceptable. |
| G3 | **Every requirement tested** | A traceability matrix links every requirement sentence in `instruction.md` to at least one test in `tests/`. "The oracle implements it" does not count as coverage. |
| G4 | **No solution leakage** | `grep -rinE "task bug|intentionally omitted|TODO|FIXME" ` over the agent-visible tree (everything the write boundary exposes) returns nothing. The regression is a **silent** omission — indistinguishable from ordinary incomplete or evolving code. |
| G5 | **Ground-truth isolation** | Expected values live in `tests/` (or a `tests/hidden_data/` equivalent) and are not readable from the agent's writable/visible path. The grader reads from `tests/`, never from anything under the agent's write boundary. |
| G6 | **No test references in `instruction.md`** | No mention of the grader, `tests/`, `test.sh`, scoring, thresholds, or "how you will be evaluated." |
| G7 | **Harbor anatomy exact** | `task.toml` complete (`schema_version "1.4"`, difficulty, timeouts), `environment/{Dockerfile,docker-compose.yaml}` present, `tests/test.sh` present and standard-shaped, `solution/solve.sh` present, `setup/regression.patch` present if the regression is patch-applied rather than baked into `environment/Dockerfile`. |
| G8 | **Solution hygiene** | `solve.sh` never reads from or writes to `tests/`; no look-ahead bias. |
| G9 | **Grader protected from the agent** | The write boundary keeps the agent from altering `tests/`, hidden fixtures, reward output, the test runner, or oracle assets — this repo's existing convention (`docs/PROJECT-SUMMARY.md`'s guardrail #1), verify it actually holds for this specific task's container. |
| G10 | **Clean reset is deterministic** | The task behaves identically after repeated regression injection, repeated seeding, repeated oracle application, and after a previous failed agent attempt. Tests pass in shuffled order. |
| G11 | **No PII, credentials, or unlicensed external assets** anywhere in the task's fixtures. |
| G12 | **Peer review sign-off** | A second person (not the task's author) has reviewed `instruction.md`, the regression, and the grader before the task is treated as calibration-ready. Self-review alone is insufficient — this repo's real gaps have all been found by someone other than the task's own author running it for real (see worked examples). |

> **G4 is the gate most likely to fail.** A planted marker or an obvious naming pattern at the edit
> site hands the agent the answer with one `grep`. Treat any pointer, however subtle, as an
> automatic block — not a minor deduction.

## Part 0.5 — Mid-build checkpoint

Before finishing the grader, pause and review these two artifacts with a second pair of eyes.
Catching problems here is far cheaper than rebuilding after a full oracle pass.

**Review the regression (`setup/regression.patch` or the baked `environment/Dockerfile` diff) for silent-omission quality:**
- Does the broken state look like ordinary incomplete or evolving code, not a deliberately removed feature?
- Would someone reading the file cold assume the missing behavior was simply never built, not stripped out for this task?
- Is the edit site free of any comment, stub name, or structural anomaly that points at what's missing?

**Review `instruction.md` for give-away risk:**
- Read it as if seeing it for the first time with no other context. Does your first instinct point straight at the fix? If yes, it's too revealing.
- Are all success criteria externally observable (HTTP response, DB row, CLI output, file state) — not "check that function X exists"?
- Is the scope tight enough to know when you're done, without naming the fix location?

Do not proceed to grader finalization if either fails this review.

## Part 1 — Build verification heuristics

Run all of these before scoring. A calibration-ready task satisfies every one.

| # | Heuristic |
|---|---|
| 1 | Regression is silent — no comment, marker, or stub name points at the missing behavior (G4). |
| 2 | Every requirement in `instruction.md` has a test that fails if that behavior is absent — no stated-but-unchecked requirement. |
| 3 | Traceability matrix complete (template below). |
| 4 | Noop, hardcoded-constant, disabled-check, and schema-only-hack probes all score `0` — each tried and logged (adversarial probe log below). |
| 5 | Threshold values, empty-state, invalid input, and compatibility paths are seeded in fixtures and actually asserted, not just described in prose. |
| 6 | Grader reads observable state — a DB row, HTTP response, or CLI/file output — never the mere existence of a class/function or a parsed log string. |
| 7 | Determinism: seeded data, fixed ordering where order isn't semantically meaningful, tolerances for floats, robust response parsing. |
| 8 | Environment is self-contained: every service, package, and seed the oracle/grader depends on is actually installed by `environment/Dockerfile` or the compose stack — nothing assumed-but-absent (this repo's own real miss: task-09's Dockerfile, mirrored from `world/fastweb/Dockerfile`, didn't install `patch`/`python3` — see worked examples). |
| 9 | `solve.sh` is portable: uses `$(dirname "$0")` or equivalent, not hardcoded mount paths; doesn't break on whitespace drift. |
| 10 | The build actually realizes the idea's scope — a high-breadth idea doesn't ship as a one-line flip. |
| 11 | Measured difficulty lands in the calibration band (`docs/mvp-scope.md`'s **0.1–0.6**, not horizon's tighter 0.2–0.4 — this project's deliberately wider MVP-stage band), and failing rollouts fail for *interesting* reasons — a wrong-but-plausible path, not a dumb one (missing file, wrong path, environment gap). |
| 12 | Every test function and non-trivial helper has a one-line docstring stating what and why. |
| 13 | `instruction.md` is professional, concise, unambiguous, and states an exact output/state contract where one exists — no fluff, no spelling errors. |
| 14 | Instruction reveal test passed: read cold by a second person (or a model with no codebase context), first-instinct response doesn't name the fix location, method, or table. |
| 15 | Regression's silent-omission quality reviewed explicitly at the Part 0.5 checkpoint. |
| 16 | Grader covers all three layers (below). |
| 17 | At least three deliberately wrong implementations tried against the grader and logged — all score `0`. |

### Requirement-to-test traceability matrix

One row per requirement sentence in `instruction.md`. Every row needs a real test name and an
observable state — "oracle implements it" is not coverage.

| Requirement (exact wording from `instruction.md`) | Test name | Observable state |
|---|---|---|
| | | |

### Three-layer grader model

- **Layer 1 — Contract**: basic stated behavior (response contains expected field, correct order,
  malformed record rejected).
- **Layer 2 — Invariant**: rules that must always hold regardless of input (this repo's task-09 is
  the sharpest example — the dedup key must always match the real cross-service contract, not just
  "differ from the first airing").
- **Layer 3 — Adversarial**: likely shortcuts and partial fixes — the exact wrong implementations
  a rushed agent (or a reward-hacking one) would try.

### Adversarial probe log

Run each before submitting. All must score `0`.

| Wrong path tried | Score | Notes |
|---|---|---|
| Noop — no changes | | |
| Hardcoded constant / fixture echo | | |
| Schema-only hack (e.g. a DB constraint standing in for real logic) | | |
| Partial fix — happy path only, skipping the discriminating edge case | | |
| Wrong side of a threshold boundary (`>` vs `>=`) | | |
| Test/config override (see task-05's real example below) | | |
| Other: | | |

### Mutation test examples

Deliberately try these; if any pass, the grader is weak:

- Check only one of the required fields/conditions and skip the others.
- Use `>` instead of `>=` at a threshold boundary, or vice versa.
- Implement the happy path but skip the edge-case branch.
- Return a plausible-looking response without actually persisting/propagating the change.
- Fix one endpoint/service in a cross-repo (Iceberg-pattern) task but not the others.
- Add an arbitrary extra field that makes two responses "differ" without deriving the field the
  real downstream consumer actually reads (task-09's real reward hack — see worked examples).
- Monkey-patch or override the test framework's own assertion behavior rather than fixing the
  underlying code (task-05's real reward hack — see worked examples).

## Part 2 — Scored review — /100

Minimum bar to treat a task as calibration-ready: **≥ 80/100, no hard-gate failures, at least one
independent agent calibration run** (`docs/mvp-scope.md` Phase 4's 10-trial `gpt-5.6-luna` run).

| Score | Band | Decision |
|---|---|---|
| 90–100 | Research-grade | Calibrate |
| 80–89 | Strong | Calibrate after minor fixes |
| 70–79 | Acceptable | Fix identified gaps first |
| 60–69 | Weak | Significant revision required |
| < 60 | Not ready | Redesign or replace |
| Any hard-gate failure | Invalid | Do not calibrate regardless of score |

### Area 1 — Task specification quality — 15 points

| Sub-criterion | Max |
|---|---|
| A. Current problem is clear — explains current behavior and why it's wrong | 3 |
| B. Desired behavior is externally observable, not implementation-prescriptive | 4 |
| C. Scope and boundaries explicit — included/excluded scope unambiguous | 3 |
| D. Edge and failure behavior defined | 3 |
| E. Compatibility expectations stated (existing response/state/client behavior) | 2 |
| **Subtotal** | **15** |

Review questions: does the instruction describe the problem, not the implementation? Could two
competent engineers independently arrive at the same intended result? Are words like "valid,"
"active," "duplicate," "recent" precisely defined? task-05's real over-reveal example is the
worked case for sub-criterion B here — see below.

### Area 2 — Broken-state authenticity — 10 points

| Sub-criterion | Max |
|---|---|
| A. Defect is realistic — plausible production regression or missing behavior | 3 |
| B. Defect is isolated but not trivialized — bounded discovery, exact line not obvious | 3 |
| C. Injection is idempotent — safe to apply repeatedly | 2 |
| D. No unrelated changes — only the intended defect plus strictly necessary infra | 2 |
| **Subtotal** | **10** |

### Area 3 — Reference-solution quality — 15 points

| Sub-criterion | Max |
|---|---|
| A. Correct against the instruction — satisfies all requirements and edge cases | 5 |
| B. Production-plausible (concurrency, tenant/session isolation, caching, validation) | 3 |
| C. Minimal and maintainable — fits existing architecture | 2 |
| D. Alternative solutions remain possible — grader doesn't require this exact structure | 2 |
| E. Idempotent application — `solve.sh` reruns safely | 2 |
| F. No hidden assumptions — schema/env/data assumptions documented | 1 |
| **Subtotal** | **15** |

Key question: would the team merge this into the real product in a normal code review? If not, it
shouldn't be the reference solution.

### Area 4 — Grader coverage and correctness — 25 points

**This is the most important area — weighted highest deliberately (see External grounding).**

| Sub-criterion | Max |
|---|---|
| A. Requirement traceability — every explicit requirement has a test | 6 |
| B. Tests real behavior — HTTP/DB/cache/filesystem state, not an internal helper that bypasses the claimed contract | 5 |
| C. Edge and boundary coverage — thresholds, empty state, invalid input, stale state seeded and asserted | 4 |
| D. Negative-path coverage — incorrect behavior rejected, state not partially mutated | 3 |
| E. Compatibility coverage — existing response shape, old flows tested | 3 |
| F. Grader independence — derived from the instruction, not copied from the oracle | 2 |
| G. Useful failure output — identifies which behavior failed without revealing the solution | 2 |
| **Subtotal** | **25** |

### Area 5 — Shortcut resistance — 10 points

| Sub-criterion | Max |
|---|---|
| A. Fixture diversity — multiple/dynamically varied; exact value can't be hard-coded | 3 |
| B. No implementation fingerprinting — grader doesn't require a specific class/function/file path | 2 |
| C. Anti-hard-coding — values vary across the fixture's natural dimensions (ids, dates, tenants) | 2 |
| D. Mutation resistance — ≥ 3 wrong implementations tried and scored 0 (logged above) | 2 |
| E. Agent can't suppress the signal — can't pass by swallowing errors or returning empty output | 1 |
| **Subtotal** | **10** |

### Area 6 — Reproducibility and isolation — 10 points

| Sub-criterion | Max |
|---|---|
| A. Offline execution — no external network dependency at grade time | 2 |
| B. Deterministic fixtures — seeds create a known state every run | 2 |
| C. Cleanup and reset — tests don't depend on run order or previous attempts | 2 |
| D. Service readiness — readiness checks target the relevant service | 1 |
| E. Flake resistance — timing, dates, concurrency, caches controlled | 2 |
| F. Resource compliance — runs within memory/timeout limits | 1 |
| **Subtotal** | **10** |

**Required reproducibility runs before calibration:**
1. Broken state → `task_success = 0`
2. Oracle → `task_success = 1`
3. Reset → broken state → `task_success = 0`
4. Oracle → `task_success = 1`
5. Tests in shuffled order → pass
6. Run tests twice without rebuilding → pass
7. Run with network disabled → pass (consistent with this repo's sealed-world design intent — see `docs/PROJECT-SUMMARY.md`'s known gap on `network_mode = "no-network"` not yet being enforced at the environment-provider level; the grader itself should not depend on network regardless)

### Area 7 — Difficulty calibration — 10 points

| Sub-criterion | Max |
|---|---|
| A. Difficulty label matches actual work — a one-line change isn't "medium" | 3 |
| B. Independent agent runs documented — model, budget, result, time recorded for ≥ 8 runs | 3 |
| C. Failure modes are informative — reveal genuine agent weaknesses, not environment/tooling failures | 2 |
| D. Task is neither trivial nor impossible for the intended agent and batch | 2 |
| **Subtotal** | **10** |

Calibration evidence table (≥ 8 runs required before this area can score above minimum — this repo's Phase 4 process runs 10 by default against the pinned `openai/gpt-5.6-luna`). Neither pass rate nor solve time is estimated up front — both are simply what the 10 runs produce:

| Run | Model | Result | Turns | Wall time | Failure reason |
|---|---|---|---|---|---|
| 1 | | | | | |
| 2 | | | | | |
| ... | | | | | |

**Pass rate:** ___ / N. **Target: 0.1–0.6** (`docs/mvp-scope.md`'s band).

**Solve time:** report the range and median wall time across all N runs (pass or fail) — read as a
description of the task, not a gate. A task that's uniformly quick (a couple of minutes) or
uniformly long (double-digit minutes, high turn counts) isn't wrong by itself, but it's worth
naming in the write-up, and a wide spread across runs is itself a signal worth investigating (per
the pilot's own finding: `gemini-3.5-flash-lite*`'s 255-turn/~16-min outlier on task-08 scored
`task_success: 1.0` just as cleanly as every other run on that task, while `openai/gpt-5.6-luna`
solved the same task in 7-13 turns every time — same pass/fail outcome, very different cost, a gap
that turn count and pass rate alone don't surface).

### Area 8 — Submission hygiene — 5 points

| Sub-criterion | Max |
|---|---|
| A. Metadata accurate — difficulty, timeouts, tags credible | 1 |
| B. Files clearly organized | 1 |
| C. Scripts are safe — strict error modes, no hardcoded mount paths | 1 |
| D. No secrets or oversized fixtures | 1 |
| E. Documentation sufficient for another engineer to run without the author present | 1 |
| **Subtotal** | **5** |

### Score summary

```
Area 1 — Task specification quality:      ___ / 15
Area 2 — Broken-state authenticity:       ___ / 10
Area 3 — Reference-solution quality:      ___ / 15
Area 4 — Grader coverage and correctness: ___ / 25
Area 5 — Shortcut resistance:             ___ / 10
Area 6 — Reproducibility and isolation:   ___ / 10
Area 7 — Difficulty calibration:          ___ / 10
Area 8 — Submission hygiene:              ___ /  5
───────────────────────────────────────────────────
TOTAL:                                    ___ / 100   (≥ 80 to calibrate)

Idea score was: ___ / 40  (docs/task-idea-rubric.md)
```

## Part 3 — Idea→build quality signal

Use the gap between the idea score and the build score as its own quality signal, not just the
build score alone:

| Idea score | Build score | Reading | Action |
|---|---|---|---|
| 28–40 | ≥ 80 | Faithful build | Calibrate if gates clear |
| 28–40 | 70–79 | Some erosion | Find which area(s) dropped and recover before calibrating |
| 28–40 | < 70 | Build under-delivered | Almost always G4 (marker) or Area 4 (untested requirements) — fix before re-scoring |

## Part 4 — Decision

```
[ ] Calibrate  (proceed to docs/mvp-scope.md Phase 4's 10-trial run)
[ ] Fix and re-review
[ ] Redesign
[ ] Drop
```

## Worked examples from this repo

Both of this repo's built tasks (`docs/ecosystem.md`) went through real hardening passes that map
directly onto this rubric's gates and areas — concrete evidence this isn't a theoretical checklist:

- **task-05, reward hack → G4 / Area 5**: an early "solve" never touched the real defect at all —
  it dropped a `vitest.config.mjs` + setup file that monkey-patched `expect.extend()` so every
  custom matcher reported `pass: true`, scoring `task_success: 1.0` against the original grader.
  Fixed by running the verifier's vitest with an explicit `--config` pointing at a trusted config
  written outside the agent's writable path — this is now a template fix that should be checked
  against **every** task in this repo (G9), not just task-05.
- **task-05, instruction over-reveal → Area 1.B**: the original `instruction.md` named
  `#EXT-X-DATERANGE` "with or without a declared duration" as marker syntax not to weaken — a hint
  guarding against the author's own first wrong approach, not a real requirement. Verified a
  simpler alternative fix passed the full grader without needing that distinction at all, meaning
  the hint wasn't load-bearing and only steered agents toward one specific failure mode. Removed.
- **task-05, anti-gaming test → Area 5.D**: added a randomized multi-break case (fresh ids,
  durations, DATERANGE/CUE-OUT ordering per run via `Math.random()`) that independently rejects two
  plausible wrong fixes — this is what a real logged mutation-test pass looks like, not a
  hypothetical.
- **task-09, reward hack → Area 4.F (grader independence)**: a "fix" that added *any*
  arbitrarily-named field (deterministic per airing, real identity fields untouched) satisfied a
  first-pass grader that only checked "the two payloads differ." Fixed by embedding a trusted,
  verbatim copy of the real cross-service dedup logic in the verifier and grading against that
  directly — exactly what "grader independence" and "tests real behavior" mean in practice.
- **task-09, scoping-fairness gap → hard gate H5-equivalent (fair discovery), Area 1.C**: closing
  the reward hack above made the task briefly unfair — nothing inside the single-repo write
  boundary let an agent discover the exact field name the real server expected. Found via a real
  `gpt-5.6-luna` run that correctly diagnosed the mechanism but named the field wrong. Fixed by
  baking a read-only reference copy of the real cross-repo contract into the image — the same
  access a real engineer fixing this bug would have.
- **task-09, environment tooling gap → Part 1, heuristic 8**: even with the reference file in
  place, the next run correctly derived the exact right fix twice, but every edit attempt silently
  failed — the task's Dockerfile (mirrored from a non-agent-facing sibling) never installed
  `patch`/`python3`. The agent then declared the task complete despite its own final check proving
  the fix never landed — an overconfidence failure worth noting alongside the environment gap.

## A known, currently-failing sub-criterion across every task built so far

Run honestly against this rubric, **every task in this repo right now would lose points on Area 4**
for one specific reason: `docs/pilot-dashboard-2026-09-07.html`'s pilot findings confirmed that
`policy_compliance` and `side_effect_safety` are `1.0` on all 60 graded pilot trials, with no
discriminating check behind either — and `correct_diagnosis` is identical to `task_success` on
every single row. Area 4.D (negative-path coverage) and the general reward-signal design this
rubric assumes both require the grader to actually check "did the agent touch anything it
shouldn't have," not report a hardcoded pass. This is real, unresolved technical debt
(`docs/PROJECT-SUMMARY.md`'s open threads) — flagged here explicitly so a task doesn't get a false
80+ by having this sub-criterion rubber-stamped rather than genuinely scored.

## External grounding

Area 4 (grader coverage and correctness) is weighted heaviest in this rubric — 25 of 100 points,
more than any other area — and that weighting is not arbitrary. It mirrors the single most
consistent finding in the published record on agentic coding benchmarks:

- SWE-bench, the most widely cited agentic coding benchmark, has been audited to show **32.67% of
  successful patches involved direct solution leakage and 31.08% passed due to inadequate test
  cases**. OpenAI's own manual audit of 138 claimed "o3 failures" against SWE-bench Verified found
  **59.4% were caused by test flaws, not model limitations** — severe enough that OpenAI recommended
  discontinuing SWE-bench Verified as a reporting benchmark. The grader, not the instruction or the
  reference solution, was the point of failure in the large majority of these cases.
- The **Agentic Benchmark Checklist**
  ([arXiv:2507.02825](https://arxiv.org/abs/2507.02825)) names **Outcome Validity** — the
  requirement that the evaluation signal faithfully reflects true task success — as one of its
  three pillars, and found flaws in it in 7 of the 10 popular benchmarks it audited.
- Separately, recent work auditing reward hackability in code RL training environments
  ([arXiv:2606.16062](https://arxiv.org/pdf/2606.16062)) documents the same failure class this
  repo hit twice independently in task-05 and task-09: agents (and in training contexts, policies)
  finding a path to a passing score that never touches the intended behavior.

This repo's own two hardening histories above are a small-sample but direct replication of that
literature's central finding — every real reward hack found here was a grader gap, not an
instruction or oracle problem, which is exactly why Area 4 outweighs every other section of this
rubric.
