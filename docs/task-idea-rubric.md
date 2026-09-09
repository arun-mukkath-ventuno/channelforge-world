# Task idea evaluation rubric

Gate a candidate task **idea** before any build time is spent on it. This is the cheap filter —
minutes of reading and scoring against grep-able repo evidence, not a Harbor run. The companion
doc, [`docs/harbor-task-eval-rubric.md`](harbor-task-eval-rubric.md), gates the **built artifact**
once an idea has cleared this one; the two are separate gates on purpose (see "Why two rubrics,
not one" below).

Sources this is distilled from: `horizon`'s `docs-for-agent/task-idea-evaluation-workflow.md`
(13-criterion `/65` rubric) and `workflow/task-idea-to-task-instruction-workflow/decision-model.md`
(its successor: 10 hard gates + 17-criterion `/85` rubric); genericized off Ventuno/Horizon-specific
tooling (Argus, Bespoke review) and re-grounded in this repo's own two built examples
(`tasks/task-05-*`, `tasks/task-09-*`, both written up in `docs/ecosystem.md`); cross-checked
against the external literature on agentic benchmark design (see "External grounding").

## Why two rubrics, not one

An idea can score well and still ship as a bad task — `horizon`'s own build data showed strong
ideas (34–53/65) losing 16–18 points at build time, most often to a planted solution marker or an
untested requirement (`docs-internal/task-build-quality-guide.md`). The idea rubric asks "is this
worth building at all" (realism, discovery shape, domain ceiling); the build rubric asks "did the
built artifact actually deliver what the idea promised, and can it be gamed." Scoring both as one
document hides exactly the gap that matters.

## Process

Three stages, each gating the next. Don't spend Stage 2/3 time on an idea that fails Stage 1.

| Stage | Who | Time | Output |
|---|---|---|---|
| 1 — Rubric score | Self or agent, from the idea description alone | ~5 min | Scored table, pass/fail |
| 2 — Desk evaluation | Human, no code | ~15 min | Checklist answers |
| 3 — Repo probe | Self or agent, against the actual vendored source | ~30 min | Probe report, build/no-build verdict |

### Stage 1 — Rubric score

Score each criterion below 1 (absent) – 5 (exemplary) against the idea description alone.

| Criterion | What it's asking | 1 (reject-leaning) | 5 (exemplary) |
|---|---|---|---|
| **Realism** | Is this a genuine defect/requirement shape a real production system would hit, not an invented puzzle? | Contrived, no plausible production path | Matches a real regression/gap class already seen in this codebase |
| **Discovery depth** | Does solving it require tracing across multiple files/services, not one obvious spot? | Single obvious file, single obvious line | Requires reading 2+ files across a real call chain to understand |
| **Shortcut resistance** | Would a noop, a hardcoded constant, or a schema-only hack score 0 against a grader built for this idea? | Any of those plausibly passes | None of those come close to passing |
| **Domain-knowledge ceiling** | Could an engineer with *zero* knowledge of this codebase solve it from general programming knowledge alone? | Yes — it's SQL parameterization/idempotency-guard/null-check shaped | No — requires this codebase's real conventions, data model, or contracts |
| **Grader strength** | Is correctness verifiable programmatically (HTTP/DB/CLI/test), not something needing an LLM judge for anything otherwise checkable? | Needs subjective judgment to score | Fully deterministic, state-based verification |
| **Buildability** | Does the infra it needs already exist in the vendored repos / current world, buildable without new upstream features? | Needs a feature or service that doesn't exist yet | Everything needed is already in `vendor/`/the world image |
| **Bounded session** | Solvable inside one Harbor agent timeout window — not a multi-session, long-horizon task? | Plausibly needs iterative exploration across many long sessions | Clearly closeable in one bounded session |
| **Novelty** | Not a near-duplicate of an existing `tasks/` (or archived) task? | Same observable problem + same root cause + same fix shape + same grader discriminator as an existing task | Materially distinct on at least one of those four dimensions |

**Threshold to proceed to Stage 2: ≥ 28/40.** (Deliberately lighter than horizon's 52/65 — this
project is calibrating its own bar as tasks go through the pipeline; tighten once several tasks
have gone through Stage 3 and the threshold's real predictive value against build-time collapse is
known — see `docs/harbor-task-eval-rubric.md`'s "Idea→build quality signal.")

**Flag immediately, regardless of total score, if:**
- Domain-knowledge ceiling scores < 3 — task will score above the target band regardless of grader
  quality (see "The domain-knowledge ceiling test" below — this is the single highest-leverage
  check in this whole rubric).
- Buildability scores < 3 — infrastructure is missing, this is greenfield work in disguise.
- Bounded session scores < 3 — scope is too large for a single agent session.

### Stage 2 — Desk evaluation

No code yet. All questions need a satisfactory answer before spending Stage-3 probe time.

**2a — The domain-knowledge ceiling test**

> If an experienced engineer with real production experience in this stack (TypeScript/Node,
> Python, Postgres) but *no knowledge of this specific codebase* read the eventual instruction,
> could they implement the correct fix from general knowledge alone?

- **Yes** → the task will score well above the target band regardless of grader quality. The fix
  is a generic, over-seen pattern. Revise or drop.
- **No** → continue.

This is not a structural pattern — it's a prerequisite ceiling test that comes before any pattern
is chosen. `horizon`'s own calibration data (`decision-model.md`) is blunt about this: a task built
on SQL parameterization, an idempotency guard, or a null check scores well above the discriminating
band *no matter how good the grader is*, because capable models have seen the pattern hundreds of
times. task-09 in this repo is the concrete worked counter-example: the fix required knowing that
`ssaiadserver`'s real dedup key includes `pod_id` — nowhere derivable from `fastworldtv`'s own
source, only from reading the actual cross-repo contract. That's what a real ceiling-clearing idea
looks like.

**2b — Discrimination check**

| Question | Must answer |
|---|---|
| Can you name the tempting wrong fix in one sentence? | Yes — if you can't, there's no discriminating layer |
| Does a partial fix plausibly fail some grader checks but pass others? | Yes — a purely bimodal 0/1 idea has no gradient to design toward |
| Is correctness verifiable via HTTP response, DB state, or CLI/file output? | Yes — anything requiring UI-only verification isn't gradable under this repo's Harbor setup |
| Are all fix points reachable from the same call chain a fair exploration would follow? | Yes — scattered fix points across unrelated subsystems are discovery friction, not difficulty (see patterns below) |

**2c — Feasibility check**

| Question | Must answer |
|---|---|
| Completable in a single agent session? | Yes |
| Depends on infrastructure absent from the current world/image? | No |
| Requires a new table, model, or endpoint not already in the vendored repos? | No (or minimal — confirmable in Stage 3) |
| Expressible as a single observable symptom? | Yes |
| Is the out-of-scope boundary clear enough to write into `instruction.md`? | Yes |
| Respects the write-boundary convention (agent touches app source only, never `environment/`, `tests/`, `solution/`)? | Yes |

**2d — Pattern identification**

Identify which structural pattern(s) this idea uses (full definitions below). **At least one must
be clearly identifiable** — an idea that fits none of these six probably lacks a discriminating
layer and will land as a flat 0/1 pass-or-fail with no real gradient.

**Pass condition for Stage 2: all 2b/2c questions answered as required, and at least one pattern identified.**

### Stage 3 — Repo probe

Prerequisites: Stage 1 passed (≥ 28/40, no critical flags), Stage 2 passed, vendored source
available (`scripts/vendor-source.sh`), idea description in hand.

Work through each section and produce a probe report:

1. **Locate** — find the specific file(s) where the fix would live. For each: path, relevant
   class/function, current line count.
2. **Confirm infrastructure** — verify every table, model, helper, and endpoint the fix depends on
   actually exists in the vendored repos or world image. List what exists, flag anything missing.
3. **Read the current state** — read the relevant code in full. Describe in 1-2 sentences what's
   actually wrong (or missing) today. Confirm it's real, not assumed — this repo's own precedent:
   task-05's original guessed defect (from `docs/fast-world-bench.md`'s blueprint) turned out not
   to exist on the refreshed codebase; the probe found a different, genuinely confirmed defect in
   the same problem area instead. That's the probe doing its job.
4. **Tempting wrong fix** — describe the naive implementation a capable agent would attempt first.
   Explain specifically why it fails — which invariant it misses, which grader check it would fail.
5. **Correct fix** — describe what the correct fix must do that the naive fix doesn't. Identify the
   invisible constraint or second failure mode the agent must discover, and where it's discoverable.
6. **Change-size estimate** — how many files, how many lines? Proportional to the intended
   difficulty label?
7. **Oracle sketch** — what does `solution/solve.sh` patch, and how? What must it not break? Can it
   apply idempotently?
8. **Grader sketch** — sketch the tests: what does each assert, which wrong implementation does
   each catch, are all offline-runnable (no external network — the whole world is meant to run
   sealed)?
9. **Offline confirmation** — confirm the grader can run fully offline. Flag anything that would
   need an external HTTP call, external API, or service not in the world image.
10. **Verdict** — Build / Needs more work / Drop. If "Needs more work," name exactly what's missing.
    If "Drop," name the blocking reason.

**Pass condition: verdict is "Build," infrastructure confirmed, grader sketch has ≥ 2 independent
discriminating checks, change size is proportional to the intended difficulty.**

## The six structural patterns

Difficulty has exactly two possible sources: **discovery friction** (don't tell the agent where to
look) or **solution complexity** (make the fix itself hard to get right). Discovery friction reads
as "not learnable" or luck-dependent — an agent who happens to explore the right directory passes,
one who doesn't fails, and the score reflects randomness, not capability. **The design goal is
always solution complexity, never discovery friction**: the bug should be locatable through fair,
normal exploration; the difficulty should live in whether the fix is *right*, not whether the agent
got lucky finding it.

| # | Pattern | Core mechanism |
|---|---|---|
| 1 | **Find it Easy, Fix it Hard** | Bug is locatable through fair exploration; the obvious implementation is subtly wrong and the grader catches it. Correct fix needs one non-obvious insight discoverable in the code (a comment, a related test, an adjacent usage pattern) but not stated in the instruction. |
| 2 | **The Plausible Trap** | Two or three implementations all look correct; the grader specifically targets the most tempting wrong one. Strongest when the wrong answer is already present in the code — commented out, deprecated, or used as a near-miss pattern elsewhere. |
| 3 | **The Invisible Constraint** | Instruction is fair and complete; the codebase has an undocumented invariant the fix must respect (a cache to invalidate, a transaction boundary, a downstream service to notify). Discoverable by reading broadly, missed by reading narrowly. |
| 4 | **Necessary But Not Sufficient** | Fixing the stated symptom is necessary but leaves a second, related failure mode active — not mentioned in the instruction, diagnosable only from the codebase. **Adjacency is required**: both failure modes must be reachable from the same function/method/call path, or this collapses into discovery friction. |
| 5 | **The Specification Reader** | Instruction describes the desired outcome but is silent on a specific edge case; correct behavior for that case is defined in existing tests, an API contract, or a related service's response schema. Rewards treating the codebase itself as the spec. |
| 6 | **The Iceberg** | Symptom surfaces in one service/repo but the real fix spans more than one (this repo's cross-repo write-boundary tasks, like task-09, are the natural home for this pattern). The entry-point fix must be real and necessary, not a decoy; every additional fix point must be reachable by following the call chain from the entry point, not by cold exploration. |

**Combining patterns**: the strongest tasks layer two so that dodging one trap still leaves the
other. Recommended default starting point — **Find it Easy Fix it Hard + Necessary But Not
Sufficient with adjacency**: plant two independent issues in the same function or immediately
adjacent code. The area is easy to find through fair exploration; the obvious fix addresses one
issue and looks complete; the second is visible to any agent that reads the surrounding code
carefully before committing, but invisible to one that patches and moves on. Avoid stacking three
or more patterns — it starts reading as unreasonable rather than difficult.

**Red flags** (signals the idea will land outside the intended difficulty band regardless of build
quality):

| Signal | Likely outcome |
|---|---|
| Fix is one file, one method, no secondary constraint | Scores high — most agents find and fix it cleanly |
| Correct fix derivable from general knowledge without reading this codebase | Scores high — domain ceiling not cleared (see 2a) |
| Insight required to fix is not discoverable anywhere in the codebase | Scores randomly — this is a lottery, not difficulty |
| Naive fix and correct fix differ on every input, not just one specific case | Probably too easy to discriminate on — the target is "same result on all but one specific input" |
| Idea only has one plausible design in the Stage-3 probe | No real discriminating layer — reconsider |

## Hard gates (binary — all must hold before build starts)

Adapted from `horizon`'s `H1-H10`/`G1-G12` gates and `docs/world-blueprint-assessment.md`'s
anti-gaming checks, scoped to what's checkable at idea stage (the build-stage gates live in
`docs/harbor-task-eval-rubric.md`):

- [ ] **No leaked bug markers planned** — the eventual instruction text won't contain "bug," "TODO,"
      "FIXME," or anything else that points at the fix location.
- [ ] **Grader/hidden-data isolation is achievable** — this repo's existing write-boundary
      convention (agent may only touch application source, never `environment/`, `tests/`,
      `solution/`) is sufficient to keep expected values out of agent-writable paths.
- [ ] **Deterministic reset is achievable** — no flaky verifier, no un-seeded randomness in the
      planned broken state.
- [ ] **No PII/credentials** anywhere the idea would need fixtures for.
- [ ] **Instructions will name symptoms, not files/lines** — service/port names are fine (navigation
      signals), implementation hints are not.
- [ ] **Idea fits an existing write boundary** — single-repo (like task-05, task-09) or a deliberate
      cross-repo (Iceberg pattern) case, not an accidental one that would let the agent edit outside
      its intended scope.

## Decision

| Verdict | Meaning |
|---|---|
| **Build** | Stages 1-3 all passed, all hard gates checked. Proceed to `docs/harbor-task-eval-rubric.md`. |
| **Needs more work** | A specific, named gap — revise the idea and re-run the failed stage only. |
| **Drop** | Structurally unsuitable (domain ceiling not cleared, no pattern fits, infra missing). Don't sink more than one revision round into an idea before dropping it. |

## Worked examples from this repo

- **task-05** (`tasks/task-05-adjacent-break-id-bleed`, write-up in `docs/ecosystem.md`): Stage 3's
  probe is exactly what found that the originally-guessed defect no longer existed post-refresh,
  and surfaced a different, genuinely confirmed one instead (`detectAvails`'s "only fill if
  undefined" guard leaking a break id forward across zero-gap back-to-back breaks) — a real example
  of the probe doing its job rather than rubber-stamping the idea as written.
- **task-09** (`tasks/task-09-repeat-ad-airing-dedup-collision`): the domain-knowledge ceiling test
  (2a) is what makes this idea genuinely hard — the fix requires knowing `ssaiadserver`'s real dedup
  key includes `pod_id`, information that doesn't exist anywhere inside `fastworldtv`'s own source.
  This is also the repo's clearest example of the Iceberg pattern (#6): the symptom (silently
  dropped duplicate analytics events) surfaces in one service, but the real contract lives in
  another.

## External grounding

This rubric's core bet — that discovery friction is a lottery and difficulty must come from
solution complexity instead — lines up with the published literature on agentic benchmark
failures, not just this project's and horizon's own experience:

- The **Agentic Benchmark Checklist** (Zhang et al., "Establishing Best Practices for Building
  Rigorous Agentic Benchmarks," NeurIPS 2025 / [arXiv:2507.02825](https://arxiv.org/abs/2507.02825))
  names **Task Validity** — a task should be solvable if and only if the agent genuinely has the
  target capability — as one of its three pillars, alongside Outcome Validity and Benchmark
  Reporting. An audit of 10 popular agentic benchmarks against this checklist found flaws in task
  validity in 7 of them. This rubric's domain-knowledge ceiling test and discrimination check are
  this project's concrete implementation of that same principle.
- **SWE-bench's** widely-cited contamination and reward-hacking findings are the cautionary case for
  the Novelty and Realism criteria above: because its tasks are mined from public repositories, a
  large fraction of issues predate model training cutoffs, and audits have found solution leakage
  and models that search GitHub for the original fix rather than deriving it. This repo's tasks
  avoid that failure mode structurally (regressions/gaps are hand-authored against a pinned,
  non-public commit, not mined from public issue trackers) — but it's the reason Novelty and the
  write-boundary hard gates matter, not just tidiness.
