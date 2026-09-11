# T2 · `ssai-live-edge-holdback` — idea-rubric evaluation

Evaluated 2026-09-11 against `docs/task-idea-rubric.md`. Tracked in GitHub issues
[#62](https://github.com/ventuno-worlds/channelforge-world/issues/62) (Stage 1),
[#63](https://github.com/ventuno-worlds/channelforge-world/issues/63) (Stage 2),
[#64](https://github.com/ventuno-worlds/channelforge-world/issues/64) (Stage 3). See
[`spec.md`](spec.md) for the idea itself.

**Result: Stage 1 flagged. Stage 2/3 not run, per the rubric's own process** ("Don't spend Stage
2/3 time on an idea that fails Stage 1" — `docs/task-idea-rubric.md`, "Process"). This is a
deliberate stop, not an oversight — see below.

## Stage 1 — Rubric score: 34/45, but 2 critical flags trip

| Criterion | Score | Note |
|---|---|---|
| Realism | 5 | Genuine live-edge-delay pattern, common in real OTT/low-latency HLS packaging |
| Discovery depth | 2 | Single obvious function, single obvious call site — nothing to trace across files |
| Shortcut resistance | 3 | A naive character/line-count trim fails the held-out checks, but a competent first attempt clears all of them easily (see below) |
| **Domain-knowledge ceiling** | **2** | See "The real problem," below |
| Grader strength | 5 | Fully deterministic manifest-structure assertions |
| Buildability | 5 | Nothing missing from `vendor/` |
| Bounded session | 5 | Trivially closeable in one session |
| Novelty | 5 | Distinct from T1 and every archived task |
| **Predicted difficulty** | **2** | See "The real problem," below |

Raw total 34/45 **clears** the ≥32/45 threshold — but per the rubric, **the four flagged criteria
override total score**: "Flag immediately, regardless of total score, if... Domain-knowledge
ceiling scores < 3... Predicted difficulty scores < 3." Both trip here. **Verdict: flagged, do not
proceed to Stage 2/3 as written.**

## The real problem: the idea description and instruction both leak the fix

This is the substance of the flag, not a formality. Two independent pieces of text hand the agent
the entire implementation before it does any discovery:

1. **The Stage-1 idea description itself** (GH #62, quoted in full in `spec.md`) names the function
   signature directly: *"Implement `holdBackManifest(body, N)`: trim newest N segments with their
   leading tags, leave MEDIA-SEQUENCE untouched, no-op when too few."* That is not a symptom
   description — it is the function name, its two parameters, and all three of its invariants,
   stated as a spec an agent could implement without reading a single other line of this codebase.
2. **The catalogue's own draft instruction** (`docs/fast-world-bench.md`) repeats the same three
   invariants explicitly: *"Do not alter `EXT-X-MEDIA-SEQUENCE`; keep each segment's leading tags
   with it; no-op if there are fewer segments than the hold-back."* This is exactly the language
   `docs/task-idea-rubric.md`'s hard gates warn against: *"Instructions will name symptoms, not
   files/lines — service/port names are fine (navigation signals), implementation hints are not."*
   These three clauses are implementation hints (the precise invariants a correct implementation
   must satisfy), not symptom descriptions.

Confirmed against the real, already-implemented `origin-rewrite.ts` (T2 is, like T1, already fixed
in the vendored source — `holdBackManifest` at `packages/data-plane/src/origin-rewrite.ts`): the
function's actual behavior is a straightforward, single-pass line-index slice — find the media
segment URI lines, keep everything up through the `(count - 1 - N)`th one, drop the rest. There is
no hidden trap in the implementation itself (no interaction bug with `detectAvails`, no ordering
issue with `absolutizeManifest`, which runs before it in `server.ts` — checked directly, no
conflict). The five items in the catalogue's own held-out verifier list are, **one-to-one**, the
five existing test names already in `origin-rewrite.test.ts` (`"trims the newest N segments"`,
`"leaves MEDIA-SEQUENCE... untouched"`, `"keeps the tags that lead each kept segment..."`, `"is a
no-op for holdBack <= 0"`, `"serves as-is... when there are too few segments"`) — meaning a Stage-3
probe here would find literally nothing an idea/instruction rewrite hasn't already stated outright.

**Domain-knowledge ceiling test (2a), answered honestly even though Stage 2 wasn't formally run**:
would an experienced engineer with general HLS/live-streaming production experience but zero
knowledge of this codebase implement this correctly, from the instruction alone? **Yes.**
"Hold the live edge back by N segments while keeping segment identity and leading tags intact" is a
well-known, widely-implemented technique in real low-latency/live HLS packaging — nothing about the
*correct* implementation here depends on this codebase's own contracts (contrast with T1, where the
`opportunityId` pod-cache dedup mechanism was genuinely undiscoverable without reading this
specific codebase). Per the rubric: *"Yes → the task will score well above the target band
regardless of grader quality... Revise or drop."*

## Recommendation

**Needs more work — revise before re-running Stage 1**, not drop outright; the underlying idea
(live-edge hold-back) is a real, realistic mechanism worth a task, the problem is entirely in how
it's currently *described*, not in the mechanism itself. Concretely:

1. Rewrite the Stage-1 idea description to state only the observable symptom ("stitched ads
   sometimes don't reach the player because newer origin segments are served before the ad is
   ready") — drop the function name, parameter names, and the three invariant clauses entirely.
2. Rewrite the catalogue instruction the same way — describe the symptom and the desired outcome
   ("serve the manifest a bit behind the true live edge"), not the three specific invariants an
   implementation must satisfy. Let the agent discover from reading `avails.ts`/`server.ts`/the
   existing (pre-regression) test file's *names* — no, the test file is hidden at grade time, so
   the agent has nothing to crib from — that MEDIA-SEQUENCE identity and tag-segment pairing matter.
3. Re-run Stage 1 against the revised text. If discovery depth and predicted difficulty still score
   low even without the explicit hints (i.e., the mechanism really is this mechanical once you read
   `origin-rewrite.ts`'s neighboring `absolutizeManifest` for the established code style), that's a
   legitimate signal to drop the idea rather than force a discriminating layer that isn't there —
   per the rubric, don't sink more than one revision round into an idea before dropping it.

**Stage 2/3 not performed** — per `docs/task-idea-rubric.md`'s explicit process guidance, no probe
time was spent past confirming the domain-ceiling test informally above (which is what surfaced the
flag in the first place, not a separate Stage-2 pass). Re-run Stage 2/3 fresh against the revised
instruction if it clears a re-run of Stage 1.
