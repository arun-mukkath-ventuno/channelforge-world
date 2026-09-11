# T1 · `ssai-live-edge-avail-completion` — idea-rubric evaluation

Evaluated 2026-09-11 against `docs/task-idea-rubric.md` Stages 1-3. Tracked in GitHub issues
[#55](https://github.com/ventuno-worlds/channelforge-world/issues/55) (Stage 1),
[#56](https://github.com/ventuno-worlds/channelforge-world/issues/56) (Stage 2), and
[#57](https://github.com/ventuno-worlds/channelforge-world/issues/57) (Stage 3). See
[`spec.md`](spec.md) for the idea itself.

## Stage 1 — Rubric score: 41/45, no critical flags

| Criterion | Score |
|---|---|
| Realism | 5 |
| Discovery depth | 4 |
| Shortcut resistance | 4 |
| Domain-knowledge ceiling | 4 |
| Grader strength | 5 |
| Buildability | 5 |
| Bounded session | 5 |
| Novelty | 5 |
| Predicted difficulty | 4 |

Passes the ≥32/45 threshold with room to spare; every flagged criterion (domain ceiling,
buildability, bounded session, predicted difficulty) clears its ≥3 floor.

## Stage 2 — Desk evaluation: pass

**2a — domain-knowledge ceiling test: No** (continue). Completing an open avail from a declared
duration is a known general SSAI pattern a generic engineer might guess, but the mechanism this
codebase actually uses to avoid double-emission — reusing the *exact same* deterministic
`opp_{channel}_{startSequence}` id (`@ssai/core`'s `opportunityId()`,
`packages/core/src/opportunity-id.ts`) for both the live-edge-completed avail and the eventual
fully-bounded one — is only discoverable by reading that contract and `server.ts`'s
`podCache.get(session, avail.opportunityId)` call site, not derivable from generic HLS/SSAI
knowledge.

**2b — discrimination check: all yes.**
- Tempting wrong fix nameable in one sentence: track "already emitted at the edge" breaks in a
  local Set/flag instead of deriving a consistent id — breaks statelessness and the pod cache's own
  dedup.
- A partial fix (CUE-OUT duration only, no DATERANGE `PLANNED-DURATION` fallback) plausibly passes
  some cases and fails others.
- Correctness is a plain object/array assertion on `detectAvails()`'s return value — no HTTP/UI
  needed.
- Every fix point sits inside the same loop/close-out path in one file.

**2c — feasibility check: all yes.** Single session; no missing infra; no new table, model, or
endpoint; single observable symptom ("break open at the live edge is dropped, no ad inserted");
clean `packages/data-plane/src/avails.ts`-only write boundary.

**2d — pattern identification:** two patterns, combined per the rubric's recommended default:
- **Find it Easy, Fix it Hard** — the gap is the obvious place to look (what happens when the
  loop's main body ends with `open` still set), but the correct extraction (DATERANGE fallback,
  `endLine` anchored to the window's last line) is easy to get subtly wrong.
- **Necessary But Not Sufficient** — completing the avail is necessary but not sufficient; the fix
  must also preserve the id contract so the *later* fetch that does see CUE-IN doesn't re-decision
  the same break. Both failure modes are adjacent — same function, same `open` variable.

## Stage 3 — Repo probe: verdict Build

1. **Locate:** `vendor/ssaiadserver/packages/data-plane/src/avails.ts`, `detectAvails()` (164
   lines total). Fix lives in the main loop's DATERANGE-metadata capture (~lines 87-91) and the
   post-loop live-edge completion block (~lines 142-161). Read-only reference:
   `packages/core/src/opportunity-id.ts` (12 lines, `opportunityId(channelId, startSequence)` →
   `` `opp_${channelId}_${startSequence}` ``).
2. **Confirm infrastructure:** everything needed already exists in `vendor/` — `parseMarkerLine`
   (`@ssai/core`), the `opportunityId()` helper, existing unit-test scaffolding (`avails.test.ts`,
   plain vitest, no runtime services required), and `server.ts`'s
   `podCache.get(session, avail.opportunityId)` consumer the fix must stay compatible with.
   Nothing missing.
3. **Read the current state:** the vendored source **already contains the fix** — this is the
   correct implementation, not the broken one, confirmed by reading the code, not assumed.
   `detectAvails()` captures `PLANNED-DURATION` off the DATERANGE-OUT into
   `open.declaredDuration` (falls back to the CUE-OUT's own duration when present), and after the
   main loop, if `open` is still set and `open.declaredDuration !== undefined`, it pushes a
   completed avail with `endLine: lines.length - 1` and an `opportunityId` built with the identical
   `opp_${channelId}_${startSequence}` format the real `opportunityId()` helper produces (written
   inline rather than calling the helper — a maintenance smell worth a one-line note in
   `instruction.md`'s "must not regress" list, but functionally identical today). `avails.test.ts`
   already has two tests covering it directly (`"completes a trailing CUE-OUT from its declared
   duration"`, `"...from the DATERANGE PLANNED-DURATION when the CUE-OUT has none"`) plus one
   confirming the pre-fix behavior stays correct for a break that never declares a duration
   (`"still drops a trailing CUE-OUT that declared no duration and has no CUE-IN"`). This matches
   the idea's own framing exactly — `break.patch` (Phase 4 build step, not done here) needs to
   revert lines ~87-91 and ~142-161 back to a CUE-OUT/CUE-IN-only detector, a clean, isolated
   revert.
4. **Tempting wrong fix:** track live-edge-completed breaks in a local `Set<string>` (or a boolean
   flag) keyed by something ad hoc (start sequence, or a synthetic timestamp-based id) to avoid
   "emitting twice," instead of relying on the deterministic id itself. Fails two ways: (a) it
   reintroduces per-instance/per-request state into what is otherwise a pure function, breaking
   under multiple SSAI instances or process restarts; (b) more concretely, when CUE-IN later
   arrives in a subsequent fetch, the "already emitted" tracking has no way to tell the caller
   "this is the *same* opportunity, don't re-decide a pod" — only a consistently-derived
   `opportunityId` lets `server.ts`'s `podCache.get(session, avail.opportunityId)` naturally
   recognize the completed avail as the one already decided, avoiding a second ad
   decision/insertion for the same break.
5. **Correct fix:** must (a) capture the declared duration from either the CUE-OUT's own value or
   the DATERANGE-OUT's `PLANNED-DURATION`, whichever is present; (b) when the loop ends with an
   avail still open and a declared duration known, emit it with `endLine` anchored to the last line
   of the window; (c) derive its `opportunityId` using the exact same `channel + startSequence`
   formula the real, later-arriving complete avail will use — the invisible constraint is that this
   id must already be correct *before* CUE-IN is ever seen, not patched up when it arrives, because
   the pod cache is the only mechanism that prevents double-decisioning and it keys purely on this
   string.
6. **Change-size estimate:** ~15-20 lines in one file (`avails.ts`) plus reading, not editing,
   `opportunity-id.ts` — proportional to a single-session, S/M-sized task.
7. **Predicted difficulty & solve time: hard solve.** The tempting wrong fix (ad hoc dedup
   tracking) is genuinely plausible and would pass a naive grader that only checks "does a second
   request avoid emitting a duplicate object," while failing a grader that checks id continuity
   *across* two separate `detectAvails()` calls simulating the window sliding forward. Estimated
   landing zone if run 10 times today: **0.1-0.6** (target band) — the fix is locatable through
   fair exploration (same function, same loop), but getting the id-continuity constraint right
   without it being stated in the instruction is a real discriminator.
8. **Oracle sketch:** `solution/solve.sh` re-applies the two removed pieces (DATERANGE
   `PLANNED-DURATION` capture + the post-loop completion block with the matching-format
   `opportunityId`) — a clean, idempotent revert of `break.patch` against a pristine, pinned
   `avails.ts`; nothing else in the file changes, so it can't collide with unrelated logic.
9. **Grader sketch:** at least four independent checks, mirroring `avails.test.ts`'s existing
   shape plus one new cross-fetch check:
   - *partial-at-edge* (CUE-OUT + declared duration, no CUE-IN) → exactly one avail, duration from
     the declared value, `endLine` at the last line.
   - *complete in one fetch* → one avail, no dupe.
   - *no break* → zero avails.
   - **new, not in the idea catalogue's original held-out list** — call `detectAvails()` twice,
     simulating the window sliding forward (edge-open fetch, then a later fetch where CUE-IN has
     now appeared), and assert both calls' `opportunityId` for that break are identical. This is
     the check that actually catches the ad hoc-dedup tempting wrong fix, which the catalogue's
     original verifier list (count/duration/bounds only) would miss.

   All are plain object/array assertions on `detectAvails()`'s return value — no HTTP, DB, or CLI
   needed.
10. **Offline confirmation:** fully offline — `detectAvails()` is a pure function over an in-memory
    string; the existing `avails.test.ts` already runs with zero network/service dependencies via
    plain `vitest`.
11. **Verdict: Build.** Infrastructure confirmed, grader sketch has 4 independent discriminating
    checks (≥2 required), change size (~15-20 lines) is proportional to the idea's own S/M sizing,
    and predicted difficulty is "hard solve" landing in the 0.1-0.6 band — not a predicted quick
    solve.

## Hard gates (idea stage) — all six checked

- No leaked bug markers planned in the eventual instruction text (confirmed against the
  instruction in `spec.md`).
- Write-boundary isolation achievable (`packages/data-plane/src/avails.ts` only, `tests/`/
  `solution/` stay hidden).
- Deterministic reset achievable (no randomness anywhere in `detectAvails()`).
- No PII/credentials involved.
- Instruction names the symptom ("break dropped at the live edge") not files/lines.
- Fits the existing single-repo write boundary (same shape as the archived `task-05`/`task-09`,
  `archive/old/tasks/`).

## Next step

Not done as part of this Stage 1-3 pass: **Stage 4** (`docs/workflow.md`) — build the actual
`tasks/ssai-live-edge-avail-completion/` Harbor task directory (`break.patch` reverting the two
blocks named in item 3 above, `instruction.md`, the 4-check grader from item 9), then **Stage 5**
(`docs/harbor-task-eval-rubric.md`) build-quality scoring before the 10-trial calibration run.
