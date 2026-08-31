# Project summary — read this first in a new session

Bootstrap doc for picking this project back up with no prior context. This is a snapshot as of
2026-08-31 — treat it as a starting map, not the source of truth; verify against the files it
points to (especially `README.md`, `AGENTS.md`, `docs/how-it-works.md`) if anything looks stale.

## What this project is

`channelforge-world` is a sealed, reproducible [Harbor](https://www.harborframework.com/docs)
evaluation "world" built on [ChannelForge](https://github.com/subbu-murugan/channelforge) — the
production VOD-to-24/7-linear control plane. An agent gets a writable checkout of ChannelForge's
real source running inside a container, is handed a bug report or feature request as
`instruction.md`, and is graded on whether its code change (plus a deliberate service restart)
fixes the behavior — verified against ChannelForge's real, pre-existing test suite.

This is a **POC for building Harbor "worlds" and tasks** — evaluation infrastructure, not a
product feature. The Notion "Channel Forge World" hub holds the fuller scope/plan; this repo is
the implementation.

## Current status (verified, not aspirational)

- **task-01 (`tasks/task-01-rights-window-bugfix`) is fully validated through real Harbor
  (0.22.0)**: `harbor run -a oracle` → `task_success: 1.0`; `harbor run -a nop` → `task_success:
  0.0`; a real agent (`terminus-2` + `gpt-5.6-luna`) also scored `1.0`, independently finding the
  same one-line bug as the reference fix (~47–52s, ~$0.0034/trial). This is the proof the whole
  model works end to end, not a plan for it to work.
- The **"Yoga & You" synthetic tenant** is built and baked into a Postgres image
  (`channelforge-world-db:yoga-and-you`): 30 assets, 6 collections, 1 published schedule (113
  events), 58 as-run entries, verified through the real API. The **scheduler runs live** (its own
  compose service, ChannelForge's real reconciliation loop) rather than having output faked —
  judged safe because its network-touching sweeps all require `channel.state == "running"`, which
  nothing in this world (no live playout-worker) ever reaches. See `docs/fixture-and-scheduler.md`.
- Only task-01 exists. No per-task DB fixture/anomaly baking is wired yet — proven mechanism,
  just not required by task-01 (its verifier is the pre-existing pytest suite, not live Postgres
  state).

## Known gaps (real, open — not cosmetic)

- **`network_mode = "no-network"` is not enforced.** The local Docker environment provider
  rejects it without an egress-control sidecar that isn't wired up. task-01 currently runs with
  `network_mode = "public"`. Nothing in task-01 makes an outbound call today, but this is a real
  gap in the isolation guarantee, not just an unused feature flag. See `docs/harbor-install.md`.
- **Reward signal is partly fake.** In `tests/test.sh`, `task_success`/`correct_diagnosis` are
  backed by a real pytest run; `policy_compliance` and `side_effect_safety` are hardcoded `1.0` —
  there's no automated check yet for "did the agent touch anything it shouldn't have." This
  matters if this world is ever used for genuine RL training (reward-hacking risk), not just
  single-shot agent evals.

## Architecture (four services, `world/docker-compose.yaml`)

| Service | Role |
|---|---|
| `main` | ChannelForge API, **writable** source tree, `pip install -e .`. No auto-reload — a deliberate `restart-api` verb is the only restart path, by design (see guardrail #2 below). Must be named `main` exactly — Harbor's own compose overlays hardcode that service name. |
| `postgres` | Blank by default; a baked `:yoga-and-you` variant carries the seeded tenant. |
| `redis` | Stock `redis:7`, unmodified. |
| `scheduler` | Same image as `main`, running `app.jobs.scheduler` live instead of the API. |

**Task variation is a source patch baked in at build time** — each task has its own
`environment/Dockerfile` that builds from pristine vendored source and applies that task's
`setup/regression.patch` as a build step (Harbor has no runtime "setup hook"). `solution/solve.sh`
(the Oracle) reverses that patch at runtime, used only to validate the task is solvable — never
shown to the evaluated agent.

**Write boundary is load-bearing, not incidental**: the evaluated agent can write ChannelForge
application source only — never `world/*/Dockerfile`, `docker-compose.yaml`, a task's
`environment/`/`tests/`/`solution/`. Each of those is a reward-hacking vector (weaken the checks
instead of fixing the bug).

**Source is vendored, not committed**: `PINNED_COMMIT` names an exact ChannelForge SHA;
`scripts/vendor-source.sh` does a `git archive` of that commit's `apps/api` + `packages` from
`../channelforge` into `vendor/` (gitignored, regenerated on demand, never a moving branch).

## Guardrails worth knowing before touching this repo (full list in `AGENTS.md`)

1. Write boundary (above) is never to be loosened.
2. **Exactly one restart command, no fallback.** This is validated, not theoretical: a migrated
   Horizon task failed a real agent run because its environment offered no single canonical
   restart command — the agent's reasonable fallback (`service apache2 restart`) started a
   process outside supervisord's control that later collided with the verifier. `restart-api`
   existing as the only path is what prevents that failure class.
3. `PINNED_COMMIT` must name an exact SHA — determinism over convenience.
4. `world/app/Dockerfile` and `world/db/Dockerfile` stay pristine and task-agnostic; a task's bug
   belongs only in that task's own `environment/Dockerfile`.
5. No live external network egress from anything inside the world, ever.
6. The Oracle and verifier are never shown to or writable by the evaluated agent.
7. **A real gotcha already hit and fixed**: `world/db/Dockerfile` sets
   `ENV PGDATA=/var/lib/postgresql/cf-data` deliberately — the base `postgres:16` image declares
   `/var/lib/postgresql/data` as a `VOLUME`, and `docker commit` never captures data inside a
   declared volume. Moving `PGDATA` off that path is what makes baking a seeded Postgres image
   actually work. Don't move it back without re-verifying a baked image boots with data intact.

## Docs map

- [`AGENTS.md`](../AGENTS.md) — implementation guardrails, read first for any repo change.
- [`docs/how-it-works.md`](how-it-works.md) — full conceptual walkthrough: folder structure, the
  `vendor/` mechanism, the exact Harbor pipeline step-by-step, `environment/Dockerfile` and
  `tests/test.sh` line-by-line for task-01.
- [`docs/setup.md`](setup.md) — local setup, booting the world, working inside a container.
- [`docs/workflow.md`](workflow.md) — how to author a new task end to end (task-01 as the worked
  example).
- [`docs/harbor-install.md`](harbor-install.md) — installing Harbor, validating a task for real,
  what corrected earlier assumptions.
- [`docs/harbor-commands.md`](harbor-commands.md) — command cheatsheet.
- [`docs/fixture-and-scheduler.md`](fixture-and-scheduler.md) — the Yoga & You tenant, the
  scheduler live-vs-baked decision, the `docker commit`/`VOLUME` gotcha in full.
- [`docs/horizon-format-migration.md`](horizon-format-migration.md) — whether a Horizon-platform
  task migrates to plain Harbor (yes, verified — see `~/Work/ventuno-labs/horizon-test/`).

## Open thread, not yet resolved

A devops/in-house division-of-labor question for the next MVP items was under discussion but not
decided as of the last session: dummy CDN files done in-house; the full services ecosystem and a
single-image no-network build handed to devops, backed by detailed documentation from this side.
No plan was confirmed and no action was taken — if this resumes, it needs a fresh decision, not an
assumed default.

## Sibling project (unrelated, do not conflate)

`~/Work/ventuno-labs/western-music` is a **separate, parallel** project: training/evaluating
open-weight models on Western music theory/notation, run independently of this repo. It shares
interest in Harbor as an eval/training-data framework but nothing else (different domain, no
shared write-boundary/task model, own `AGENTS.md`/docs). Don't bolt music-world work onto this
repo or vice versa.
