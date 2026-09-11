# T1 · `ssai-live-edge-avail-completion` — task idea spec

Status: **idea stage, Stages 1-3 passed (Build verdict)**. Not yet built as a real Harbor task
directory — see [`evaluation.md`](evaluation.md) for the rubric evaluation, and `docs/workflow.md`
for what Stage 4 (the actual build) looks like when it happens.

Catalogue source: `docs/fast-world-bench.md`, T1 of the T1-T10 idea catalogue
(`docs/mvp-scope.md` Phase 3 backlog).

## Repo / files

- **Repo:** `ssaiadserver`
- **File:** `packages/data-plane/src/avails.ts` (+ its test file, `avails.test.ts`)
- **May edit:** `packages/data-plane/src/avails.ts` only

## The break (Phase 4 build step, not yet applied)

Reverts the end-of-loop "open avail completion" logic in `detectAvails()` — the detector would only
emit an avail when it has seen *both* CUE-OUT and CUE-IN, and drops `PLANNED-DURATION` capture off
the DATERANGE-OUT marker. Concretely, this means reverting:

- The DATERANGE-metadata capture that sets `open.declaredDuration` from `PLANNED-DURATION`
  (`avails.ts` ~lines 87-91 as of the 2026-09-11 pins).
- The post-loop live-edge completion block that pushes a completed avail when the loop ends with
  an avail still open and a declared duration known (~lines 142-161).

## Instruction (draft, as it will appear in `instruction.md`)

> When an ad break's CUE-IN hasn't yet appeared in the media playlist (the break is still in
> progress at the live edge), the SSAI drops the break entirely and no ad is inserted. Make avail
> detection recognize a break that is open at the live edge, using its signalled duration, so the
> break is still returned — and don't emit a break twice once its CUE-IN later arrives.

No mention of `PLANNED-DURATION`, `endLine`, or `declaredDuration` — those are implementation
details the agent must discover, not hints.

## Held-out verifier (original catalogue list)

- **partial-at-edge** (CUE-OUT + PLANNED-DURATION, no CUE-IN) → exactly one avail, duration from
  the declared value, end anchored at the last line.
- **complete** (CUE-OUT and CUE-IN both present in one fetch) → one avail, no dupe.
- **no break** → zero avails.
- **two breaks, second open at edge** → two avails, correct durations, no dupes.

See `evaluation.md` item 9 for a 4th check added during the Stage 3 probe (cross-fetch id
continuity) that the original list above doesn't cover.

## Anti-cheat

Assertions on returned avail objects (count/duration/bounds), never on which lines the code reads;
test cases mounted only at grade time.

## Budget

~150k tokens / ~40 steps.

## Tier / provenance

Core (~0.35 target `task_success`) · ssai live-edge completion (idea catalogue #10 in
`docs/fast-world-bench.md`'s numbering).

## Write boundary

Single-repo (`ssaiadserver` only) — same shape as the archived `task-05`/`task-09`
(`archive/old/tasks/`), not the colocated cross-repo model.
