# FAST World POC — scope and step breakdown

Living scope doc for the current replan (2026-09-03 onward). Supersedes nothing — it builds on
`docs/ecosystem.md` (integration contracts, task-01..04 history) and `docs/world-blueprint-
assessment.md` (the external readiness review this scope is reacting to). Update this file as
each step actually happens; it's the scope-of-record, not a one-time snapshot.

## Context

The original ecosystem-wiring plan (vendor 3 repos, compose them, write task-01..04) is done and
merged. Since then: all three upstream repos shipped a real burst of work (43/10/11 commits ahead
of our pins — see `docs/ecosystem.md`'s 2026-09-03 status note), a two-channel live pipeline now
genuinely airs (ChannelForge → ssaiadserver → fast-world-tv, channels 101/102), and an external
readiness review (`docs/world-blueprint-assessment.md`) assessed the gap between "strong app MVPs"
and "reproducible RL world" — plus proposed a 10-task portfolio (FW-001..010).

The goal now: refresh the world to current upstream, build 5 of those tasks, and get **real
comparative data** across several models before deciding what a bigger benchmark looks like.

Decisions locked so far:

- **Verifier fidelity: code/API-level** (task-02/03's proven style — no live HLS stream required).
- **Task set: FW-001, FW-002, FW-003, FW-004, FW-006** — all five execute with services already in
  `world/docker-compose.yaml` (`ssai-control`/`ssai-data`/`ssai-postgres`/`ssai-redis`/`fast-web`
  fed by static fixture manifests) or ChannelForge's own API+DB alone. None need the still-missing
  playout-worker/object-storage/edge — that gap only blocks FW-005/FW-008, which are excluded.
- **Run scale: pilot first**, then the full 10×5×5 matrix once the pilot validates the harness.
- **Model roster**: see Step 3 below — narrowed to a short list, final pick pending confirmation.

## Step 1 — Refresh the world to current upstream

**2026-09-05 rescope**: all three repos moved again since the plan above was first written —
46/11/17 commits ahead of the *original* pins now, not the 43/10/11 the 2026-09-03 status note
recorded. Current HEADs: ChannelForge `3c5599a`, ssaiadserver `3ce4632`, fast-world-tv `6d09506`.
Two changes land in this refresh that affect Step 2's task design, not just the repin:

- **fast-world-tv's channel API is now async and store-backed.** `getChannel`/`listChannels`/
  `guide` used to read a static `CHANNELS` array; they now read an admin-editable
  `channel-config-store` and return Promises (`6d09506`, the "v2 app shell" rebuild). Any task
  template that asserts against fast-world-tv's channel/schedule code needs to target this shape,
  not the old sync array — this is real re-vendor work, not a mechanical bump.
- **All 5 channels are now real** (103 Art All The Way, 104 Ventuno Mix replacing the retired
  "Food Shorts TV" both wired to live ChannelForge origins + SSAI sessions) — closes the
  `world-blueprint-assessment.md` gap that said 3/5 were still public test streams. Doesn't change
  the fixture-first task design decision below, but a live capture is now available as a fixture
  source for any channel, not just 101/102.

Steps, updated:

1. Bump `PINNED_COMMIT_CHANNELFORGE`/`PINNED_COMMIT_SSAIADSERVER`/`PINNED_COMMIT_FASTWORLDTV` to
   `3c5599a`/`3ce4632`/`6d09506` (or later HEAD if more lands before this runs), then
   `scripts/vendor-source.sh`.
2. Re-verify task-01..04 still apply/reverse cleanly at the new pins (same check already done once
   when the ChannelForge pin was first bumped — see `docs/ecosystem.md`) *before* archiving them,
   so we know what we're archiving still worked, not silently broken.
3. Bring up `world/docker-compose.yaml` fresh; fix anything the new commits broke in the two glue
   patches (`world/patches/*.patch`) — in particular, `channelforge-ssai-base-url.patch` is now
   superseded by upstream's own real `CF_SSAI_BASE_URL`/admin-login wiring (see `docs/ecosystem.md`
   correction) and should probably be retired rather than carried forward as dead code.
4. **Sample data**: the user is providing real fixture data (extending the existing "Yoga & You"
   pattern in `scripts/seed_fixture.py`/`scripts/bake-fixture-db.sh` — real prod-derived asset
   titles/durations baked into a Postgres image so trial reset = recreate-from-image, not
   reseed-at-runtime). Wire it into that same script once handed over; don't design the loader
   until the actual data/shape is in hand.
5. Update `docs/ecosystem.md`'s pin references and "Known gaps" section to match the new pin SHAs
   and whatever the re-verification in step 2 finds.

## Step 2 — Author 5 new tasks, archive the old 4

For each of FW-001/002/003/004/006, follow the same investigate-first process task-01..04 used
(read the real current code, confirm the defect or design the synthetic regression against real
behavior, verify both a broken and fixed state by hand before trusting Harbor) — do not assume the
blueprint's one-paragraph spec is exactly buildable as written; adapt it to what the current
vendored code actually supports, the way task-03's org-scoping scenario and task-04's postcss fix
both required adaptation mid-build.

- **Template**: task-03's colocated-`main` cross-repo shape
  (`tasks/task-03-org-scoped-origin-drift/`) for FW-001/002/003/006 (all genuinely cross-repo:
  ChannelForge+SSAI or SSAI+TV) — both source trees in one `main` container, code-level verifier
  (new pytest/vitest files written at verify time, run alongside each repo's existing relevant
  test file), `task_success` requires all sides to pass. Static fixture manifests (hand-built
  `.m3u8` with the relevant cue/pod/session shapes, following task-02's "captured from the real
  function's own output" discipline) stand in for a live origin. Any fast-web-side assertion must
  now go through the async `channel-config-store` accessors (`6d09506`), not the retired sync
  `CHANNELS` array.
- FW-004 (ChannelForge+TV) may end up single-write-boundary if the actual defect is ChannelForge-
  only (own-side EPG/schedule regeneration state) with a fast-web-side assertion checked at the
  code level rather than requiring a live `fast-web` container — decide this per task-01 vs.
  task-02's precedent (write boundary follows where the real bug lives, not assumed up front).
  **2026-09-05**: ChannelForge shipped real rights management since the blueprint was written
  (`4c99050` — policies, assignments, takedowns). FW-004 can now hook into that actual feature
  instead of simulating rights state, which makes the verifier more credible — read `4c99050`
  before authoring to confirm the takedown → EPG/playout consistency path it enables.
- **FW-001** (alternate CUE-OUT syntax losing `break_id` correlation): ChannelForge just shipped
  `e9d86a9` "globally-unique interval-break ids," a real fix in exactly this area. Read that commit
  before designing the seeded defect — if it already closes the bug the blueprint had in mind,
  FW-001 becomes "write a regression test that pins this fix" (still a legitimate task); if it
  fixes a different failure mode, the original defect framing still stands.
- Name the new directories `tasks/task-05-<slug>` .. `tasks/task-09-<slug>` (keep the existing
  numbering scheme; don't reuse FW-00N as the directory name since it doesn't match this repo's
  own convention).
- **Instruction wording**: apply the task-03 lesson directly — state the scope boundary and
  correctness bar precisely, never name the exact file/function. Measure each task's real turn
  count with a non-oracle agent run before calling it done, same as every prior task.
- **Archive task-01..04**: `git mv tasks/task-0{1,2,3,4}-* archive/old/tasks/`. Leave
  `docs/ecosystem.md`'s existing write-ups for them as historical record (they document real,
  verified findings — turn-depth data, the task-03 instruction-wording experiment — worth keeping
  as reference), but add a one-line note at the top of each section that the task itself now lives
  under `archive/old/tasks/` and is no longer part of the default `tasks/` sweep.
  **Why this matters operationally, not just cosmetically**: Harbor's `-p` flag takes one task-or-
  dataset-directory path, and `harbor run -p tasks/ -m ... -k ...` sweeps every task found under
  it — archiving is what makes `-p tasks/` mean "just the 5 new ones" without needing
  `--include-task-name` filtering on every run.

**Out of scope for this POC despite being new capability**: ssaiadserver's VAST ingestion slice
(`3ce4632`) and its from-scratch React/shadcn admin console rebuild are real, but neither feeds
FW-001/002/003/004/006 — noted as a possible Tier-3 candidate later, not pulled into this pass.

## Step 3 — Model roster

Confirmed working so far: `openai/gpt-5.6-luna` (paid, reliable, every prior real-agent run) and
`openrouter/minimax/minimax-m3:free` (free, works, but rate-capped — 20 req/min / 50 req/day per
key, and a single task-03 run already burned ~75+ requests). Groq is a confirmed dead end (8,000
TPM cap incompatible with terminus-2's growing context — `docs/model-providers.md`).

**2026-09-03 — evaluated OpenRouter's current free-model catalog for 1-3 more picks.** Filtered
for agentic-coding fit, real usage (avoids the `glm-5.2` congestion pattern hit earlier), and not
about to be deprecated:

| Model | Fit | Why |
|---|---|---|
| `poolside/laguna-s-2.1:free` | **Strong** | Purpose-built coding-agent model — 70.2% Terminal-Bench 2.1, 40.4% DeepSWE. Closest benchmark match to what `terminus-2` actually does. 262K context. |
| `cohere/north-mini-code:free` | **Strong** | Trained specifically to generalize across agent harnesses (OpenCode, SWE-Agent) — same category of workload. Small (3B active) → cheap/fast turns, less likely to blow a rate-limit budget mid-trajectory. 256K context. |
| `nvidia/nemotron-3-ultra-550b-a55b:free` | Stretch | #15-ranked in Programming (best of the catalog scanned), 1M context, built for agent orchestration/coding. Caveat: 55B active + very high usage (4.67T tokens/7d) — like `glm-5.2`, popularity may mean shared-pool congestion, the same failure mode already hit once. Try it, but have a fallback ready. |
| `nvidia/nemotron-3.5-lightning:free` | Fallback | If Nemotron Ultra turns out congested — 3B active/30B total, 1M context, still agentic-workload-oriented. |
| `dots-studio/dots-3-note-preview:free` | Skip | Flagged "going away September 30, 2026" — don't build data around an expiring model. |
| `liquid/lfm-2.5-2.6b:free`, `nvidia/nemotron-3.5-content-safety:free` | Skip | Liquid's own docs advise against agentic coding; the NVIDIA one is a content-moderation/guardrail model, not a coding agent. |
| `z-ai/glm-5.2:free` | Already known-bad | Confirmed upstream 429 congestion earlier this session — don't retry. |

**Locked 2026-09-05 — 4 models**, per the team's requested mix (1 frontline OpenAI, 1 mid-level
OpenAI, 2 free OpenRouter): `openai/gpt-6-astra` (frontline — newest OpenAI generation on the
account's key, confirmed live), `openai/gpt-5.6-luna` (mid-level — already proven across every
prior real-agent run), `openrouter/minimax/minimax-m3:free` (proven free), `openrouter/poolside/
laguna-s-2.1:free` (best untested benchmark fit). `cohere/north-mini-code:free` and the Nemotron
stretch pick dropped — see `docs/model-providers.md` for the full rationale. All OpenRouter picks
run on the existing `OPENROUTER_API_KEY` — no new keys needed.

Given the free-tier request-count math, the pilot (step 4) should default to running each
free-tier model as its own low-concurrency `harbor run` invocation, not mixed into one
high-concurrency sweep — a paid model like `gpt-5.6-luna` can run at higher `-n`/concurrency
without hitting a wall.

## Step 4 — Pilot run, then the full matrix

**Pilot** (validate the harness before committing to 250 runs): all 5 new tasks × 2-3 of the
confirmed-working models × 3 attempts. Harbor natively supports the sweep — no custom orchestrator
needed:

```
harbor run -p tasks/ -a terminus-2 -m <model> -k 3 -n <concurrency> -e docker -y \
  --env-file .env --jobs-dir jobs/pilot-2026-09-XX
```

(`-p tasks/` sweeps every task under the now-archived-down directory; `-m` accepts one model per
invocation — run one invocation per model so concurrency/timeout can be tuned per provider's real
rate limits; `-k` is Harbor's native "attempts per trial" — this *is* the "seeds" dimension, no
separate seeding mechanism needed.)

Add `scripts/summarize-runs.py` (new): walks a `--jobs-dir` tree, and for every trial pulls
`task_success` (+ the other three reward dimensions) from `verifier/reward.json`, turns/tool-calls
from `agent/trajectory.json` (same method as every prior real-agent measurement in this repo —
non-empty-`tool_calls` steps = turns, sum of each step's `tool_calls` length = tool-call count),
wall time, total prompt/completion tokens, and any recorded exception (e.g. `AgentTimeoutError`).
Emits one row per (task, model, attempt) as CSV + a markdown summary table.

After the pilot: read a sample of the actual trajectories per (task, model) cell directly (not a
separate LLM-summarization pipeline — at pilot scale, ~15-45 trials, direct reading is cheap and
more trustworthy than automating a summarizer we haven't validated), and write up findings the
same way `docs/ecosystem.md`'s task-03 section already does: which tasks/models produced correct-
and-deep trajectories, which failed and why (genuine task ambiguity vs. model limitation vs. rate-
limit/timeout artifact), and whether turn counts landed in the 30-150 target.

**Only after the pilot's harness/tasks/models are confirmed sound**: scale to the full 10 attempts
× 5 tasks × (3-5 models) matrix, same command shape with `-k 10` and every confirmed model. This is
explicitly a second, separate phase — not committed to as part of this same pilot — gated on what
the pilot finds.

## Critical files

- `PINNED_COMMIT_CHANNELFORGE` / `PINNED_COMMIT_SSAIADSERVER` / `PINNED_COMMIT_FASTWORLDTV`,
  `scripts/vendor-source.sh` — repin + re-vendor.
- `world/patches/channelforge-ssai-base-url.patch` — likely retire (superseded upstream).
- `scripts/seed_fixture.py`, `scripts/bake-fixture-db.sh` — extend once the user's sample data
  arrives.
- New: `tasks/task-05-*` .. `tasks/task-09-*`, each following `tasks/task-03-org-scoped-origin-
  drift/`'s file layout (`instruction.md`, `task.toml`, `environment/{Dockerfile,docker-
  compose.yaml}`, `setup/*.patch` if a regression shape, `solution/solve.sh`, `tests/test.sh`).
- `archive/old/tasks/` (new) — task-01..04 moved here via `git mv`.
- `docs/ecosystem.md` — pin/gap updates, archive-location notes on task-01..04's sections, new
  sections for task-05..09 in the same style as the existing ones.
- New: `scripts/summarize-runs.py`.
- `docs/model-providers.md` — record whichever additional models get picked and their real pilot
  results, same as the existing Groq/OpenRouter entries.
- New: a pilot-results write-up doc once the pilot completes (exact name TBD — likely
  `docs/pilot-results-2026-09-XX.md`, or folded into `docs/ecosystem.md`).

## Verification

- Step 1: `docker compose -f world/docker-compose.yaml up -d --build` — all services healthy;
  task-01..04's regression patches still apply/reverse byte-identically at the new pins before
  they're archived.
- Step 2: each new task, same bar as every prior one — `harbor run -a oracle` → `task_success: 1`
  on all four reward dimensions, `harbor run -a nop` → `task_success: 0`, then one real
  `terminus-2`/`gpt-5.6-luna` run to confirm it's solvable and record its real turn count before
  moving on to the next task.
- Step 4: the pilot itself is the verification step for steps 1-3 combined — if tasks/models/
  harness are all sound, the pilot's summary table should show sane `task_success` variance across
  models (not all-0 or all-1, which would mean a broken task or a broken model hookup) and turn
  counts in a plausible range, before scaling to the full matrix.

## Status

- [ ] Step 1 — world refresh to `3c5599a`/`3ce4632`/`6d09506` (not started; blocked on sample data
      handoff for full completion, but re-pin/re-vendor/compose-bring-up can start independently)
- [ ] Step 2 — 5 new tasks + archive old 4 (not started; FW-001 and FW-004 framing pending a read
      of `e9d86a9` and `4c99050` respectively before authoring)
- [x] Step 3 — model roster locked: `gpt-6-astra`, `gpt-5.6-luna`, `minimax-m3:free`,
      `laguna-s-2.1:free` (2026-09-05)
- [ ] Step 4 — pilot run (blocked on steps 1-3)

## Rescope log

- **2026-09-05**: repos moved again (46/11/17 commits ahead of original pins). fast-world-tv's
  channel API went async/store-backed and all 5 channels are now real (see Step 1 note above).
  ChannelForge shipped a break-id fix (`e9d86a9`) relevant to FW-001 and real rights management
  (`4c99050`) relevant to FW-004 (see Step 2 notes above). No change to verifier fidelity, task
  set, or run-scale decisions — repin targets and two tasks' framing updated only.
