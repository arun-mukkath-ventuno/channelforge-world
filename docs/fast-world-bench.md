# FAST World — Agentic Eval Bench (planning)

> **Status:** planning / draft for team review.
> **Branch:** all bench work lives on `eval/fast-world-bench` (and equivalent side branches in
> `ssaiadserver` / `fast-world-tv`) so the public-facing `main` in each repo ships unchanged.
> This document is the working spec; we expand it section by section (see *Open items* at the end).

## Concept (one line)

A hermetic **"FAST world" image** bundling `channelforge` + `ssaiadserver` + `fast-world-tv` at
pinned commits, on top of which each **Harbor task** introduces a defect or a stubbed feature; a
**behavioral verifier** decides pass/fail; we run **4 models × 3 trials** and keep only tasks whose
solve rate lands in **0.2–0.6** (discriminative — not saturated, not impossible).

## Why this world is worth showing labs

Most coding benches are single-repo, single-language, pure application logic. This world stresses
things those miss, which is the pitch:

- **Protocol correctness** — HLS manifests, SCTE-35 (CUE-OUT/CUE-IN/DATERANGE), VAST, XMLTV.
  Wrong-but-plausible is easy; correct requires reading the spec-shaped code.
- **Timing / live-edge reasoning** — the origin's PROGRAM-DATE-TIME timeline lags wall-clock;
  breaks live at the edge of a sliding window. Agents that don't model time fail in ways unit tests
  catch cleanly.
- **Cross-service contracts** — a `break_id` threads avail → DATERANGE → SSAI → reconciliation
  across three repos and two languages. Great for testing whether an agent can hold a system in its
  head.
- **Web-platform gotchas** — CORS preflight, `sendBeacon` content-types, reverse-proxy ordering.
  Symptom → root-cause debugging, not feature-writing.
- **Three languages** (Python / TypeScript / Next.js) in one world.

And crucially: these are **real bugs and features we actually built and debugged**, so each has a
natural ground-truth fix and naturally-calibrated difficulty.

## The world image (base environment)

- All three repos at pinned commits; all deps pre-installed (pip, npm) so the sandbox is **offline**.
- Services runnable via compose: postgres/redis/minio/caddy, ssai control/data/creative-worker,
  CF api/worker, plus the **fixture-origin** so nothing depends on the public internet.
- **Seeded fixtures:** the 4 channels, 8 campaigns, 11 creatives, and — critically — **recorded HLS
  manifests with synthetic PDT offsets** so timing tasks are deterministic instead of depending on a
  live ffmpeg clock. This is the single biggest lever for stable calibration; flaky verifiers wreck a
  0.2–0.6 target.
- Deterministic knobs pinned: `AD_DECISION_SEED`, `SSAI_LIVE_EDGE_HOLDBACK`, `SSAI_LOOP_TO_FILL`.

## Harbor task anatomy + verifier principles

Each task dir: instruction prompt · the mutated starting state (a reverted fix or a stubbed
function) · a **held-out verifier** (tests the agent can't read/overfit) · resource limits.

Verifier rules that keep the bench honest:

1. **Behavioral, not implementation-shaped** — assert the manifest contains both cue markers / the
   beacon gets recorded / reconciliation matches, never "you edited function X."
2. **Held-out variants** — calibrate against inputs the agent never sees, so memorizing a visible
   fixture doesn't pass.
3. **Anti-trivial-revert** — for tasks seeded from a real commit, scrub the commit message/history
   from the image so the fix isn't a `git log` away.
4. **Deterministic** — seeded RNG, frozen clocks, recorded manifests.

## The world image, in depth

**One base image, optional services.** `fast-world-base:<sha>` contains all three repo trees + all
deps pre-installed (pip venv + npm `node_modules`), offline. Most tasks run a *scoped unit/contract
test* with **no services up** — fast, hermetic, dead-stable. Integration tasks (beacons,
reconciliation, manifest stitching) do a `compose up` of only the named services *inside* the same
image. It is not "container vs. stack" — it is one image that can optionally light up the stack per
task.

**Determinism is the whole game.** The enemy is the live ffmpeg clock and the sliding live window:

- **Recorded manifests, not live playout** — capture a set of real HLS media playlists (at-edge
  break, complete break, no break, thin-inventory break) once, rewrite their PROGRAM-DATE-TIME to
  **synthetic fixed offsets**, and freeze them as fixtures. Timing tasks read these, never a running
  origin.
- **Frozen clock** — verifiers inject `now` rather than calling the wall clock.
- **Seeded decisioning** — `AD_DECISION_SEED` pinned so the ad pod is identical every run.
- **Seeded DB** — a SQL dump of the 4 channels / 8 campaigns / 11 creatives loaded at image build,
  not scraped from prod at runtime.

**Pinning strategy.** A top-level `worldspec.json` records the exact commit SHA + lockfile hash per
repo, plus the base-image digest. Rebuilding the world from `worldspec.json` is reproducible;
bumping the world is a deliberate, reviewed change.

**Repo layout inside the image — (c) hybrid (chosen).** Vendored snapshots of each repo's tree at
its pinned SHA are copied into the image for full hermeticity, and `worldspec.json` records the SHAs
for provenance. This gives reproducibility without git-submodule friction, and history is scrubbed
by construction (vendoring drops `.git`), which also satisfies the anti-trivial-revert rule — there
is no `git log` back to the fix. *Alternatives considered:* (a) vendored-only (loses provenance
linkage), (b) submodules (clean provenance but submodule friction and a scrubbing burden to stop the
agent walking history to the fix).

## Harbor task structure (detailed)

> **Assumption for this draft:** Terminal-Bench / Laude-style **Harbor** runner (Dockerized
> rollouts with a `tests/` verifier convention) and **binary pass/fail** per rollout. If the runner
> is in-house, the layout below still holds — only the `task.yaml` keys and verifier entrypoint
> convention need to conform to that contract. Partial scoring is described at the end as an option.

**A Harbor task is one directory:**

```
tasks/ssai-live-edge-avail-completion/
  task.yaml            # id, name, difficulty tag, services needed up, timeouts, resource caps
  instruction.md       # the prompt the agent sees (symptom + acceptance criteria, no fix hints)
  environment/         # how the world is prepared for THIS task
    Dockerfile         # FROM fast-world-base:<pinned>  +  applies the "break" patch
    break.patch        # reverts the real fix / stubs the function → the starting state
  solution/            # the reference fix (our eyes + a "gold" sanity run); NEVER in the agent image
  tests/               # the held-out verifier — mounted at grade time, not visible during the run
    verify.sh          # entrypoint: runs the scoped test, emits pass/fail (+ optional score)
    cases/             # held-out inputs (crafted manifests, expected outputs)
```

**Environment / resource contract, pinned per task:**

- Base image `fast-world-base:<sha>` (built once, cached); the task layer only applies `break.patch`
  and stages `tests/` out of the agent's reach.
- Declares which services must be **up**. Most tasks: none — they run a scoped unit/contract test.
  Integration tasks (e.g. beacons, reconciliation) bring up only the named services.
- Wall-clock + token/step caps; **no network egress** (the image is offline).
- The verifier runs as a **separate step after** the agent's turn ends, against a `tests/` tree the
  agent never had mounted — so it can't be read, edited, or overfit.

**Grading signal.** Default is **binary** pass/fail per rollout (cleanest input to the 0.2–0.6 mean
across 12 rollouts). Where Harbor supports a non-binary result, a verifier may additionally emit a
**partial score** (e.g. "3 of 4 held-out cases") — this smooths calibration and exposes *how* a
model fails, without changing the pass/fail gate used for the band.

## Calibration protocol

- 4 models × 3 trials = 12 rollouts → solve rate.
- **< 0.2** (too hard / underspecified / flaky): add a little scaffolding, clarify the spec, split
  into two tasks, or fix verifier flakiness. Check it's *difficulty*, not a broken harness.
- **> 0.6** (too easy): remove hints, widen the surface (more files), tighten the invariant, add an
  adversarial held-out input.
- Track **variance across trials** too — a task that's 0/3 on one model and 3/3 on another is more
  interesting (discriminative) than uniform 0.4.

### Calibration mechanics (operational)

- **The 4 models** — a deliberate spread of capability tiers, not four peers (e.g. one frontier, one
  strong-mid, one small/open, one prior-gen). The point is *discrimination*: a task all four pass, or
  all four fail, tells us nothing.
- **The metric** — per task, 12 rollouts → **mean solve rate** is the band gate (0.2–0.6). We also
  record **per-model pass@3** and the **spread across models**, because a task at mean 0.4 that is
  3/3 frontier and 0/3 small is *more valuable* than a uniform 1.5/3 everywhere. Discrimination, not
  just difficulty.
- **Flakiness gate (non-negotiable)** — any task whose **gold solution** (our reference fix) doesn't
  pass **3/3** is disqualified until the verifier is deterministic. A flaky verifier poisons the band.
- **Remediation loop — always diagnose harness before difficulty.** A task out-of-band runs a fixed
  checklist before we touch difficulty: (1) is the verifier flaky? (re-run, check variance);
  (2) is it underspecified? (read failed transcripts for "I didn't know X was required"); (3) *only
  then* adjust scaffolding / surface / invariant.
- **What we log per task** — a small results table (model × trial → pass/fail + score + wall-clock +
  tokens) so calibration is auditable and the lab-facing report is a byproduct, not extra work.

### Band policy — (b) soft gate + tiers (chosen)

We keep a wider spread but **label** tiers rather than hard-dropping everything outside the band:

- **core** — mean 0.2–0.6. The discriminative heart of the bench; what we lead with.
- **stretch** — mean < 0.2. Kept as *frontier-only* signal / hard anchors (only the strongest model
  makes progress).
- **warm-up** — mean > 0.6. Kept for a weaker-model floor and as easy anchors.

A lab often *wants* a few saturating and a few brutal tasks as anchors; hard-dropping them loses
signal. *Alternative considered:* (a) hard gate — drop anything outside 0.2–0.6 after one remediation
pass; cleaner and smaller, but throws away useful anchor signal.

## The 10 tasks

Difficulty is a hypothesis for the target band — the whole point is to calibrate. Deliberately
spread across repos, languages, and task types (fix / feature / debug-from-symptom / cross-repo).

| # | Task | Repo / lang | Type | Verifier | Est. band |
|---|------|-------------|------|----------|-----------|
| 1 | **Live-edge avail completion** — detect an ad break whose CUE-IN is still beyond the live edge (emit an open CUE-OUT avail from PLANNED-DURATION) without double-emitting when CUE-IN later appears | ssai `avails.ts` / TS | fix | Held-out crafted playlists (partial-at-edge, full, none) → correct avails, zero dupes | Med (0.35) |
| 2 | **Live-edge hold-back** — implement `holdBackManifest(body, N)`: trim newest N segments *with* their leading tags, leave MEDIA-SEQUENCE untouched, no-op when too few | ssai `origin-rewrite.ts` / TS | feature | Segment count −N, sequence unchanged, tags stay attached, idempotent on short input | Med (0.4) |
| 3 | **Loop-ads-to-fill pod** — when inventory < break, repeat ads in order to fill, stop when shortest ad > remaining, slate only the tail, no infinite loop | ssai `pod.ts` / TS | feature | Pod duration ≈ break, order preserved, slate at tail only, terminates on a huge break | Med (0.45) |
| 4 | **SCTE-35 dual markers** — origin emits only DATERANGE; add CUE-OUT/CUE-IN so SSAI/players detect breaks, and size the live window so both are co-visible | CF `cue_schedule`/`ffmpeg` / Py | fix | Generated playlist over a break has both markers, right duration/placement, window ≥ break | Med-Hard (0.3) |
| 5 | **break_id threading + reconciliation** — make `BRK-{ver[:8]}-{idx:04d}` globally unique, stamp it into the DATERANGE ID, match it on delivery import | CF api, cross-file / Py | fix | Schedule + simulated SSAI report → per-break match, zero orphans | Hard (0.25) |
| 6 | **VAST macro validation** — reject undocumented macros (closed allowlist), resolve the 7 documented ones per-avail, never emit PII | CF `adapters/ssai.py` / Py | feature | Good template resolves correctly; `{FOO}` rejected naming the macro; PII never appears | Med (0.5) |
| 7 | **Beacons never arrive** *(symptom → root cause)* — quartile beacons record 0 events; fix the `sendBeacon` JSON-Blob preflight by sending text/plain + add a server-side text/plain parser | fwtv `ssai.ts` + ssai `server.ts` / TS | debug | POST text/plain event → 202 + impression recorded; OPTIONS → 204 | Hard (0.25) |
| 8 | **Scrubber sits 40s ahead** *(timing)* — markers ahead of the ad; parse newest PDT (`originNow`) and reckon break state against `videoNow`, keep the guide axis on wall-clock | fwtv `ads/current` + `fast-view` / TS | fix | Playlist with fixed PDT lag + avail → marker aligns to origin, guide axis still wall-clock | Hard (0.3) |
| 9 | **Caddy preflight 401** *(infra reasoning)* — bare `respond @options` loses to the catch-all `handle {}`; make OPTIONS a `handle` block ordered first | ssai `Caddyfile` / infra | debug | OPTIONS on events path → 204; normal request still authenticates | Hard/niche (0.2) |
| 10 | **EPG break-extended timings** — published XMLTV programme stop times must reflect break-extended aired duration, staying DTD-conformant | CF api `epg` / Py | fix | XMLTV boundaries match expected extended times + validates against DTD | Med-Hard (0.35) |

### Re-check against the re-pinned `world`-branch source (2026-09-11, T1.3)

Since `main` was merged into each repo's `world` branch (T1.1/T1.2), re-verified whether each
task's underlying defect still exists in current source, since these are `break.patch`-style
tasks (a real fix is intentionally reverted at build time, so finding the fix present in current
source is the *expected*, healthy state — it confirms there's something real to revert):

**T1-T9: fix confirmed present in current source** — `avails.ts:142-161` (T1's live-edge
completion), `origin-rewrite.ts:48-61` (T2's `holdBackManifest`), `pod.ts:85-106` (T3's
`loopToFill`), `cue_schedule.py:73-86` + `ffmpeg.py:143,254,337` (T4's dual markers + widened HLS
window), `schedules.py:405-412` + `reconciliation.py` (T5's break-id format + matching),
`adapters/ssai.py:23-24,60-61,101,129` (T6's macro allowlist), `ssai.ts:43-55` +
`server.ts:91-97` (T7's text/plain beacon fix — this file was one of T1.2's 2 hand-resolved
merge conflicts; the parser survived intact), `ads/current/route.ts:19,100-104` (T8's
`originNow` reckoning), `Caddyfile:20-28` (T9's `handle @options` ordering). **Before trusting
any of these for Phase 3 task authoring, actually test that the task's `break.patch` still
applies cleanly and reverts the fix as designed — this was a source-inspection check, not a
patch-apply test.**

**T10: still genuinely unfixed, no revert possible.** `apps/api/app/services/epg.py`'s own
docstring says the break-extended resolver "land[s] later"; grepped `services/` for
`aired_end`/`break_extended`/`extended_end` — zero hits, `EpgProgramme.end` is used as-is with no
break-duration adjustment anywhere. There is nothing to revert here — re-scope T10 as a
build-from-scratch feature task, not a fix/break-patch task, when it's authored.

Side note for whoever authors T5: `schedules.py:465,543` references a `world_ids.break_id_prefix`
helper that looks like it may already partially consolidate break-id generation as part of the
`world` blueprint work — check it doesn't duplicate T5's literal `f"{id_prefix}-{avail_index:04d}"`
inline format at `schedules.py:317` before authoring.

### Alternate bench (swap-ins if any calibrate out of band)

- Copy-mode FLV codec-tag remux bug (CF, real yoga #61).
- Origin-only cert gate evaluated at worker spawn (CF #158) — a nice "why won't it start" debug.
- SSAI reconciliation aggregate wiring.
- HDR / 10-bit tonemapping detection (CF engine).

### Notes on the spread

- **Tasks 1–3** — self-contained TS logic (lower-risk, likely to land mid-band).
- **4 / 6 / 10** — Python spec-correctness.
- **5** — the cross-repo contract centerpiece.
- **7 / 8 / 9** — debugging-from-a-symptom; tend to be hardest and most differentiating. These are
  the ones that most impress a lab if a frontier model *can* do them and weaker ones can't.

## Per-task specs

**Per-task template.** Each spec carries: *repo / files in play* · **files the agent may edit
(allowlist)** · *the break* (what `break.patch` reverts or stubs) · *instruction* (agent-facing
symptom + acceptance criteria, no fix hints) · *held-out verifier* · *anti-cheat* · **token / step
budget** · *tier hypothesis + provenance*. The allowlist bounds the edit surface (edits outside it
are rejected at grade time); the budget caps agent interaction so a task can't be brute-forced by
unbounded trial-and-error.

---

### T1 · `ssai-live-edge-avail-completion`
- **Repo / files:** `ssaiadserver` · `packages/data-plane/src/avails.ts` (+ its test file)
- **May edit:** `packages/data-plane/src/avails.ts`
- **The break:** reverts the end-of-loop "open avail completion" logic — the detector only emits an
  avail when it has seen *both* CUE-OUT and CUE-IN, and drops `PLANNED-DURATION` capture.
- **Instruction:** *"When an ad break's CUE-IN hasn't yet appeared in the media playlist (the break
  is still in progress at the live edge), the SSAI drops the break entirely and no ad is inserted.
  Make avail detection recognize a break that is open at the live edge, using its signalled
  duration, so the break is still returned — and don't emit a break twice once its CUE-IN later
  arrives."* (No mention of `PLANNED-DURATION`, `endLine`, or `declaredDuration`.)
- **Held-out verifier:** *partial-at-edge* (CUE-OUT + PLANNED-DURATION, no CUE-IN) → exactly **one**
  avail, duration from the declared value, end anchored at the last line; *complete* → one avail, no
  dupe; *no break* → zero; *two breaks, second open at edge* → two avails, correct durations, no
  dupes.
- **Anti-cheat:** assertions on returned avail objects (count/duration/bounds), never on which lines
  the code reads; cases mounted only at grade time.
- **Budget:** ~150k tokens / ~40 steps.
- **Tier / provenance:** core (~0.35) · ssai live-edge completion (#10).

**Idea-rubric evaluation (2026-09-11, `docs/task-idea-rubric.md` Stages 1-3 — GH #55/#56/#57):**

*Stage 1 — rubric score: **41/45**, no critical flags.* Realism 5, Discovery depth 4, Shortcut
resistance 4, Domain-knowledge ceiling 4, Grader strength 5, Buildability 5, Bounded session 5,
Novelty 5, Predicted difficulty 4. Passes the ≥32/45 threshold with room to spare; every flagged
criterion (domain ceiling, buildability, bounded session, predicted difficulty) clears its ≥3 floor.

*Stage 2 — desk evaluation: pass.*
- **2a domain-knowledge ceiling — No** (continue): completing an open avail from a declared duration
  is a known general SSAI pattern a generic engineer might guess, but the mechanism this codebase
  actually uses to avoid double-emission — reusing the *exact same* deterministic
  `opp_{channel}_{startSequence}` id (`@ssai/core`'s `opportunityId()`, `packages/core/src/
  opportunity-id.ts`) for both the live-edge-completed avail and the eventual fully-bounded one — is
  only discoverable by reading that contract and `server.ts`'s `podCache.get(session,
  avail.opportunityId)` call site, not derivable from generic HLS/SSAI knowledge.
- **2b discrimination** — all yes: tempting wrong fix nameable in one sentence (track "already
  emitted at the edge" breaks in a local Set/flag instead of deriving a consistent id, which breaks
  statelessness and the pod-cache's own dedup); a partial fix (CUE-OUT duration only, no DATERANGE
  `PLANNED-DURATION` fallback) plausibly passes some cases and fails others; correctness is a plain
  object/array assertion on `detectAvails()`'s return value, no HTTP/UI needed; every fix point sits
  inside the same loop/close-out path in one file.
- **2c feasibility** — all yes: single session, no missing infra, no new table/model/endpoint,
  single observable symptom ("break open at the live edge is dropped, no ad inserted"), clean
  `packages/data-plane/src/avails.ts`-only write boundary.
- **2d pattern identification** — two patterns, combined per the rubric's recommended default:
  **Find it Easy, Fix it Hard** (the gap is the obvious place to look — what happens when the loop's
  main body ends with `open` still set — but the correct extraction, with the DATERANGE fallback and
  `endLine` anchored to the window's last line, is easy to get subtly wrong) layered with
  **Necessary But Not Sufficient** (completing the avail is necessary but not sufficient — the fix
  must also preserve the id contract so the *later* fetch that does see CUE-IN doesn't re-decision
  the same break; both failure modes are adjacent, same function, same `open` variable).

*Stage 3 — repo probe: verdict **Build**.*
1. **Locate:** `vendor/ssaiadserver/packages/data-plane/src/avails.ts`, `detectAvails()` (164 lines
   total; the fix lives in the main loop's DATERANGE-metadata capture, lines ~87-91, and the
   post-loop live-edge completion block, lines ~142-161). Read-only reference:
   `packages/core/src/opportunity-id.ts` (12 lines, `opportunityId(channelId, startSequence)` →
   `` `opp_${channelId}_${startSequence}` ``).
2. **Confirm infrastructure:** everything needed already exists in `vendor/` — `parseMarkerLine`
   (`@ssai/core`), the `opportunityId()` helper, the existing unit-test scaffolding
   (`avails.test.ts`, plain vitest, no runtime services required), and `server.ts`'s
   `podCache.get(session, avail.opportunityId)` consumer that the fix must stay compatible with.
   Nothing missing.
3. **Read the current state:** the vendored source **already contains the fix** — this is the
   correct implementation, not the broken one. Confirmed real, not assumed: `detectAvails()`
   captures `PLANNED-DURATION` off the DATERANGE-OUT into `open.declaredDuration` (falls back to the
   CUE-OUT's own duration when present), and after the main loop, if `open` is still set and
   `open.declaredDuration !== undefined`, it pushes a completed avail with `endLine: lines.length -
   1` and an opportunityId built with the identical `opp_${channelId}_${startSequence}` format the
   real `opportunityId()` helper produces (written inline rather than calling the helper — a
   maintenance smell worth a one-line note in `instruction.md`'s "must not regress" list, but
   functionally identical today). `avails.test.ts` already has two tests covering it directly
   (`"completes a trailing CUE-OUT from its declared duration"`, `"...from the DATERANGE
   PLANNED-DURATION when the CUE-OUT has none"`) plus one confirming the pre-fix behavior stays
   correct for a break that never declares a duration (`"still drops a trailing CUE-OUT that
   declared no duration and has no CUE-IN"`). This matches the idea's own framing exactly — the
   task's `break.patch` (Phase 4 build step, not done here) needs to revert lines ~87-91 and
   ~142-161 back to a CUE-OUT/CUE-IN-only detector, which is a clean, isolated revert.
4. **Tempting wrong fix:** track live-edge-completed breaks in a local `Set<string>` (or a boolean
   flag) keyed by something ad hoc (start sequence, or a synthetic timestamp-based id) to avoid
   "emitting twice," instead of relying on the deterministic id itself. This fails two ways: (a) it
   reintroduces per-instance/per-request state into what is otherwise a pure function, which breaks
   under multiple SSAI instances or process restarts; (b) more concretely, when CUE-IN later arrives
   in a subsequent fetch, the "already emitted" tracking has no way to tell the caller "this is the
   *same* opportunity, don't re-decide a pod" — only a consistently-derived `opportunityId` lets
   `server.ts`'s `podCache.get(session, avail.opportunityId)` naturally recognize the completed
   avail as the one already decided, avoiding a second ad decision/insertion for the same break.
5. **Correct fix:** must (a) capture the declared duration from either the CUE-OUT's own value or
   the DATERANGE-OUT's `PLANNED-DURATION`, whichever is present; (b) when the loop ends with an avail
   still open and a declared duration known, emit it with `endLine` anchored to the last line of the
   window; (c) derive its `opportunityId` using the exact same `channel + startSequence` formula the
   real, later-arriving complete avail will use — the invisible constraint is that this id must
   already be correct *before* CUE-IN is ever seen, not patched up when it arrives, because the pod
   cache is the only mechanism that prevents double-decisioning and it keys purely on this string.
6. **Change-size estimate:** ~15-20 lines in one file (`avails.ts`) plus reading, not editing,
   `opportunity-id.ts` — proportional to a single-session, `S`/`M`-sized task.
7. **Predicted difficulty & solve time:** **hard solve** — the tempting wrong fix (ad hoc dedup
   tracking) is genuinely plausible and would pass a naive grader that only checks "does a second
   request avoid emitting a duplicate object," while failing a grader that checks id continuity
   *across* two separate `detectAvails()` calls simulating the window sliding forward. Estimated
   landing zone if run 10 times today: **0.1-0.6** (target band) — the fix is locatable through fair
   exploration (same function, same loop), but getting the id-continuity constraint right without it
   being stated in the instruction is a real discriminator.
8. **Oracle sketch:** `solution/solve.sh` re-applies the two removed pieces (DATERANGE
   `PLANNED-DURATION` capture + the post-loop completion block with the matching-format
   opportunityId) — a clean, idempotent revert of `break.patch` against a pristine, pinned
   `avails.ts`; nothing else in the file changes, so it can't collide with unrelated logic.
9. **Grader sketch:** at least four independent checks, mirroring `avails.test.ts`'s existing shape
   plus one new cross-fetch check: (a) *partial-at-edge* (CUE-OUT + declared duration, no CUE-IN) →
   exactly one avail, duration from the declared value, `endLine` at the last line; (b) *complete in
   one fetch* → one avail, no dupe; (c) *no break* → zero avails; (d) **new, not in the idea
   catalogue's original held-out list** — call `detectAvails()` twice, simulating the window
   sliding forward (edge-open fetch, then a later fetch where CUE-IN has now appeared) and assert
   both calls' `opportunityId` for that break are identical — this is the check that actually catches
   the ad hoc-dedup tempting wrong fix, which the catalogue's original verifier list (count/duration/
   bounds only) would miss. All are plain object/array assertions on `detectAvails()`'s return
   value — no HTTP, DB, or CLI needed.
10. **Offline confirmation:** fully offline — `detectAvails()` is a pure function over an in-memory
    string; the existing `avails.test.ts` already runs with zero network/service dependencies via
    plain `vitest`.
11. **Verdict: Build.** Infrastructure confirmed, grader sketch has 4 independent discriminating
    checks (≥2 required), change size (~15-20 lines) is proportional to the idea's own `S`/`M`
    sizing, and predicted difficulty is "hard solve" landing in the 0.1-0.6 band — not a predicted
    quick solve.

**Hard gates (idea stage):** all six checked — no leaked bug markers planned in the eventual
instruction text (confirmed against the existing catalogue instruction above); write-boundary
isolation achievable (`packages/data-plane/src/avails.ts` only, `tests/`/`solution/` stay hidden);
deterministic reset achievable (no randomness anywhere in `detectAvails()`); no PII/credentials
involved; instruction names the symptom ("break dropped at the live edge") not files/lines; fits the
existing single-repo write boundary (same shape as task-05/task-09's `ssaiadserver`-only tasks).

**Next step (not done here, out of scope for this Stage 1-3 pass):** Stage 4
(`docs/workflow.md`) — build the actual `tasks/ssai-live-edge-avail-completion/` directory
(`break.patch` reverting lines ~87-91/~142-161, `instruction.md`, the 4-check grader from item 9
above), then Stage 5 (`docs/harbor-task-eval-rubric.md`) build-quality scoring before the 10-trial
calibration run.

### T2 · `ssai-live-edge-holdback`
- **Repo / files:** `ssaiadserver` · `packages/data-plane/src/origin-rewrite.ts`, wired in `server.ts`
- **May edit:** `packages/data-plane/src/origin-rewrite.ts`, `packages/data-plane/src/server.ts`
- **The break:** `holdBackManifest` stubbed to return the body unchanged and its call site removed /
  env knob unread.
- **Instruction:** *"Stitched ads sometimes don't reach the player because the origin's newest
  segments are served before the ad is ready. Serve the manifest a fixed number of segments behind
  the true live edge. Do not alter `EXT-X-MEDIA-SEQUENCE`; keep each segment's leading tags with it;
  no-op if there are fewer segments than the hold-back."*
- **Held-out verifier:** segment count −N; `MEDIA-SEQUENCE` unchanged; leading tags (EXTINF,
  PROGRAM-DATE-TIME, DISCONTINUITY) stay attached to their segment; idempotent on short input; N=0 is
  identity.
- **Anti-cheat:** assertions on output manifest structure; held-out N values.
- **Budget:** ~180k tokens / ~45 steps.
- **Tier / provenance:** core (~0.4) · ssai hold-back (#11).

### T3 · `ssai-loop-ads-to-fill`
- **Repo / files:** `ssaiadserver` · `packages/core/src/pod.ts` (+ `decide.ts` passthrough, test)
- **May edit:** `packages/core/src/pod.ts`
- **The break:** the `loopToFill` branch is removed — after the first greedy pass, any remainder is
  always slate.
- **Instruction:** *"When ad inventory is shorter than the break, repeat ads in order to fill it
  instead of running a long slate. Stop when the shortest remaining ad no longer fits; slate only the
  leftover. It must always terminate."*
- **Held-out verifier:** pod duration within tolerance of the break; ads repeat in original priority
  order; slate only at the tail; an adversarially huge break terminates (guard; timeout = fail);
  inventory ≥ break keeps prior behavior.
- **Anti-cheat:** held-out inventory/break combos including the infinite-loop probe.
- **Budget:** ~180k tokens / ~45 steps.
- **Tier / provenance:** core (~0.45) · ssai loop-to-fill (#12).

### T4 · `cf-scte35-dual-markers`
- **Repo / files:** `channelforge` · `services/playout-worker/worker/cue_schedule.py`, `scte35.py`,
  `ffmpeg.py`
- **May edit:** `cue_schedule.py`, `scte35.py`, `ffmpeg.py`
- **The break:** origin emits only `EXT-X-DATERANGE`; `CUE-OUT`/`CUE-IN` emission removed and the HLS
  window (`hls_list_size`) reverted small.
- **Instruction:** *"SSAI and players that rely on `EXT-X-CUE-OUT`/`CUE-IN` don't detect this
  channel's ad breaks — only `DATERANGE` is emitted. Emit `CUE-OUT` (with duration) at the break
  start and `CUE-IN` at the end alongside `DATERANGE`, and make the live window large enough that both
  are visible together for the whole break."*
- **Held-out verifier:** a generated playlist across a break has both markers; `CUE-OUT` carries the
  break duration; `CUE-IN` at break end; window length ≥ break; `DATERANGE` still present.
- **Anti-cheat:** held-out break lengths; assert on emitted manifest, not function internals.
- **Budget:** ~250k tokens / ~60 steps.
- **Tier / provenance:** core, med-hard (~0.3) · CF barker/window fixes (#182 / #184).

### T5 · `cf-breakid-threading-reconciliation`
- **Repo / files:** `channelforge` · `services/cue_plan.py` (break_id origin), `services/schedules.py`,
  `services/ssai_delivery.py`, `services/reconciliation.py`
- **May edit:** `cue_plan.py`, `schedules.py`, `ssai_delivery.py`, `reconciliation.py`
- **The break:** `break_id` reverted to an index-only (non-unique) form and not stamped into the
  `DATERANGE` id; reconciliation matches on the wrong key → every break is an orphan.
- **Instruction:** *"Reconciliation can't match SSAI-reported breaks to scheduled avails — every
  break shows as an orphan. Make each break's id globally unique and thread it so the id on the
  origin's `DATERANGE` equals the id the reconciler matches against the SSAI delivery report."*
- **Held-out verifier:** a published schedule + a simulated SSAI delivery report keyed by the
  `DATERANGE` id → per-break matches, zero orphans; two schedule versions don't collide.
- **Anti-cheat:** held-out schedule version + report; assert the match set, not the id format string.
- **Budget:** ~400k tokens / ~80 steps (cross-file).
- **Tier / provenance:** stretch, hard (~0.25) · the `BRK-{ver[:8]}-{idx:04d}` threading work.

### T6 · `cf-vast-macro-validation`
- **Repo / files:** `channelforge` · `apps/api/app/adapters/ssai.py`
- **May edit:** `apps/api/app/adapters/ssai.py`
- **The break:** `validate_ad_tag_template` and `resolve_ad_tag` stubbed (accept anything / no
  substitution).
- **Instruction:** *"Implement per-channel VAST tag templates. Only a fixed set of macros is
  allowed — `CHANNEL_ID`, `PROGRAMME_ID`, `AVAIL_ID`, `BREAK_ID`, `DURATION`, `TERRITORY`,
  `CONTENT_GENRE`. Reject a template containing any other macro, naming the offending one; resolve
  the allowed macros per avail; never emit personal data."*
- **Held-out verifier:** a valid template resolves to the expected URL; `{FOO}` is rejected with
  `FOO` named; each of the 7 documented macros resolves; an undocumented/PII-shaped macro is rejected.
- **Anti-cheat:** held-out templates; assert on resolved output + the raised error's content.
- **Budget:** ~200k tokens / ~50 steps.
- **Tier / provenance:** core (~0.5) · VAST provisioning (slice 4).

### T7 · `fwtv-beacons-never-arrive` *(cross-repo, symptom → root cause)*
- **Repo / files:** `fast-world-tv` · `src/lib/ssai.ts` (`sendAdBeacon`) **+** `ssaiadserver` ·
  `packages/control-plane/src/server.ts` (`/v1/events` + content-type parsing)
- **May edit:** `fast-world-tv/src/lib/ssai.ts`, `ssaiadserver/packages/control-plane/src/server.ts`
- **The break:** the client sends an `application/json` Blob (forces a CORS preflight the beacon
  path can't satisfy), and the server has no `text/plain` body parser (so any such body is dropped).
- **Instruction:** *"Ad quartile beacons record zero events on the server even though playback fires
  them. Diagnose and fix it so beacons reliably reach `/v1/events` and are recorded."* (No mention of
  CORS, preflight, or content-type.)
- **Held-out verifier:** *integration* — bring up the control-plane; a POST to `/v1/events` with the
  beacon's real body shape returns **202** and increments the event/impression count; the client's
  `sendAdBeacon` emits a body that qualifies as a **CORS-simple** request (no forced preflight).
- **Anti-cheat:** verify the recorded event in the store, not code shape; held-out event payloads.
- **Budget:** ~400k tokens / ~80 steps (service up, cross-repo).
- **Tier / provenance:** stretch, hard (~0.25) · beacon content-type fix (ssai #13 + fw #7).

### T8 · `fwtv-scrubber-origin-timeline` *(timing)*
- **Repo / files:** `fast-world-tv` · `src/app/api/fast/ads/current/route.ts`, `src/lib/fast-view.ts`
  (+ the `fast-client` type)
- **May edit:** `src/app/api/fast/ads/current/route.ts`, `src/lib/fast-view.ts`,
  `src/lib/fast-client.ts`
- **The break:** reverts `originNow`/`videoNow` — the route doesn't return `originNow` and the view
  reckons break state against wall-clock `now`.
- **Instruction:** *"The ad-break marker on the scrubber sits ~40s ahead of where the ad actually
  plays. Fix the marker so it aligns to where the break appears in the video, while the guide's time
  axis stays on wall-clock."*
- **Held-out verifier:** a recorded media playlist whose newest `PROGRAM-DATE-TIME` lags a fixed
  offset behind the injected `now`, plus an avail on the origin timeline → the computed break state /
  marker aligns to the origin (`originNow`), and the guide window still ticks on wall-clock.
- **Anti-cheat:** held-out PDT offsets + avail times; assert computed marker vs. expected, not
  variable names.
- **Budget:** ~300k tokens / ~70 steps.
- **Tier / provenance:** core, hard (~0.3) · scrubber alignment (fw #8).

### T9 · `ssai-caddy-preflight-ordering` *(infra reasoning)*
- **Repo / files:** `ssaiadserver` · `deploy/caddy/Caddyfile`
- **May edit:** `deploy/caddy/Caddyfile`
- **The break:** OPTIONS is handled by a bare `respond @options 204` that the catch-all `handle {}`
  shadows (Caddy orders `handle` before `respond`) → preflight returns 401.
- **Instruction:** *"A CORS preflight (OPTIONS) to the events endpoint returns 401, blocking browser
  beacons. Make preflight succeed while normal requests still authenticate."*
- **Held-out verifier:** `caddy validate` passes; a request harness against the running config → an
  OPTIONS to the events path returns **204**, and a normal request to a protected path still
  authenticates (401 without creds).
- **Anti-cheat:** behavioral request test; held-out — a second protected path must also still auth.
- **Budget:** ~250k tokens / ~60 steps.
- **Tier / provenance:** stretch, niche (~0.2 — calibration risk, may sit below band) · Caddy OPTIONS
  ordering (ssai #9).

### T10 · `cf-epg-break-extended-timings`
- **Repo / files:** `channelforge` · `apps/api/app/services/epg.py`
- **May edit:** `apps/api/app/services/epg.py`
- **The break:** XMLTV generation ignores break durations, so programme stop times reflect
  content-only duration and drift from the aired timeline.
- **Instruction:** *"Published XMLTV programme stop times must account for ad breaks that extend a
  programme's on-air duration, so the EPG matches what actually airs. The output must stay
  DTD-conformant."*
- **Held-out verifier:** generate XMLTV for a schedule with known breaks → programme start/stop
  boundaries match the expected break-extended times, and the output validates against the XMLTV DTD.
- **Anti-cheat:** held-out schedule with different break placement; assert boundaries + DTD validity.
- **Budget:** ~300k tokens / ~70 steps.
- **Tier / provenance:** core, med-hard (~0.35) · *confirm against current `epg.py` behavior before
  authoring — may be built as a forward-looking task if the gap is already handled.*

## Lab-facing pitch

**One-liner.** A real, three-service streaming product — delivery origin, ad server, player — turned
into an agentic bench where the tasks are the actual bugs and features we shipped. The provenance is
the credibility: these are not synthetic puzzles.

**What it measures that SWE-bench-style benches don't.** Most coding benches are single-repo,
single-language, application logic. This world leads with a **novel eval surface**:

- **Protocol / spec correctness** — HLS, SCTE-35, VAST, XMLTV. Wrong-but-plausible is easy; correct
  needs the spec-shaped code read properly.
- **Live-edge timing reasoning** — the origin's PROGRAM-DATE-TIME timeline lags wall-clock and breaks
  sit at the edge of a sliding window; agents that don't model time fail in ways the verifier catches.
- **Cross-service contracts** — a `break_id` threads avail → DATERANGE → SSAI → reconciliation across
  3 repos and 3 languages; the task is whether the agent can hold the whole system in its head.
- **Web-platform symptom → root-cause** — CORS preflight, `sendBeacon` content-types, reverse-proxy
  ordering: debugging from a symptom, not writing a feature.

**Why it's credible (the realism backbone).** Every task derives from a real shipped fix, so the
ground truth and the difficulty are natural rather than invented — a genuinely realistic agentic-SWE
setting, three languages, a running multi-service world.

**The discrimination story.** A calibrated **0.2–0.6 core** plus **stretch / warm-up** anchors, with
per-model spread — the bench *separates* frontier from mid from small, which is exactly what a team
evaluating a new model wants (not just an average, but *which* capabilities move the needle).

**Headline tasks** — the "if your model can do this, it genuinely understands the system" showcase:
T7 (beacons — cross-repo debug), T8 (scrubber timing), T5 (cross-service contract).

**What a lab gets.** The world image + N calibrated tasks + held-out verifiers + a reproducible
`worldspec.json`, runnable **offline**; per-task results tables fall out of calibration as a byproduct.

**Honest boundaries.** Small task count at first (10, designed to grow); domain-specific
(streaming / adtech — a feature, since it's underrepresented in existing benches, but stated plainly);
and we authored it, so held-out verifier rigor and the gold-3/3 flakiness gate are how the bench
stays honest.

## Scope & logistics

**Home for the bench — (a) standalone repo (chosen).** A new `fast-world-bench` repo vendors the
three product repos at their pinned SHAs and holds the tasks, verifiers, `worldspec.json`, harness,
and the base-image build. Cleanest separation: the three product repos stay pristine, and this
planning doc migrates into the new repo once it exists. *Alternative considered:* (b) a subtree in
`channelforge` — less setup, but couples the bench to CF and muddies that repo.

**Task-count trajectory.** Ship **v0** with these **10 calibrated**; grow to **~25–30** for a v1
bench (the alternates + new seeds mined from more of the git history).

**Build sequence (phased):**

1. Build `fast-world-base` image + `worldspec.json` + the recorded-manifest fixtures.
2. Stand up the Harbor harness on **one reference task (T1) end-to-end**, including the **gold-3/3
   gate**.
3. Author the remaining 9 (each: `break.patch` + instruction + held-out verifier).
4. Calibrate 4 × 3 → assign tiers (core / stretch / warm-up).
5. Generate the results tables → the lab-facing report.

**Authoring vs. review split.** The author writes the break + instruction + held-out verifier; a
**second reviewer** validates it "can't see the fix," confirms the gold solution passes **3/3**, and
checks the instruction leaks no hint. No task ships un-reviewed.

**Branch / CI plan.** Bench work stays on `eval/fast-world-bench` side branches (and the standalone
repo); CI builds the base image and runs **all gold solutions (must be 3/3)** on every change; public
`main` in all three product repos ships untouched.

**Rough effort.** ~0.5–1 day authoring per task + calibration compute (12 rollouts × N tasks),
front-loaded by the one-time base-image + harness build.

---

## Open items to expand (walking through with the team)

These sections are stubs we'll fill in one by one:

- [x] **Harbor specifics** — exact task-dir layout, verifier harness, environment/resource contract.
      *(See "Harbor task structure (detailed)" above. Assumes T-Bench-style runner + binary grading;
      revisit if the in-house runner contract differs.)*
- [x] **World image, in depth** — single hermetic container vs. full compose stack; how timing tasks
      stay deterministic (recorded manifests + synthetic PDT); build + pinning strategy.
      *(See "The world image, in depth" above. Repo layout = (c) hybrid: vendored trees +
      `worldspec.json` provenance.)*
- [x] **Calibration mechanics** — the 4 models, pass@k vs. mean solve rate, variance handling, the
      out-of-band remediation loop. *(See "Calibration mechanics (operational)" + "Band policy"
      above. Chosen: (b) soft gate + core/stretch/warm-up tiers.)*
- [x] **Per-task detail** — for each of the 10: the exact defect/stub, the instruction prompt, the
      held-out verifier assertions, anti-cheat notes, edit allowlist, and token/step budget.
      *(See "Per-task specs" above. T10 flagged to confirm against current `epg.py`.)*
- [x] **Lab-facing pitch** — the story these tasks tell and which ones carry it. *(See "Lab-facing
      pitch" above. Leads with (a) novel eval surface, folds in (b) realism as the credibility
      backbone.)*
- [x] **Scope / logistics** — total task count, timeline, authoring vs. review split, branch/CI plan.
      *(See "Scope & logistics" above. Home = (a) standalone `fast-world-bench` repo.)*

_All planning topics expanded. Next: stand up `fast-world-bench` (base image + harness + T1 gold run)._
