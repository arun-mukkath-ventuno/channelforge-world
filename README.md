# channelforge-world

A sealed, reproducible [Harbor](https://www.harborframework.com/docs) evaluation world built on
[ChannelForge](https://github.com/subbu-murugan/channelforge) — the production VOD-to-24/7-linear
control plane. An agent gets a writable checkout of ChannelForge's real source running inside the
world, is handed a bug report or feature request, and is graded on whether its code change (plus a
deliberate service restart) actually fixes the behavior — verified against the real test suite.

See the Notion "Channel Forge World" hub for the full scope/plan docs. This repo is the
implementation; Notion is the plan.

- [`AGENTS.md`](AGENTS.md) — implementation guardrails for anyone (human or agent) building or
  extending this repo. Read this first.
- [`docs/setup.md`](docs/setup.md) — local setup, booting the world, working inside a container,
  troubleshooting.
- [`docs/workflow.md`](docs/workflow.md) — how to author a new task end to end, using task-01 as
  the worked example.
- [`docs/harbor-install.md`](docs/harbor-install.md) — installing Harbor, validating a task for
  real (`harbor run -a oracle`/`-a nop`), and what we learned that corrected earlier assumptions.
- [`docs/how-it-works.md`](docs/how-it-works.md) — the conceptual walkthrough: what every piece of
  this repo actually does, and the full pipeline Harbor runs through for a task, explained from
  first principles.
- [`docs/horizon-format-migration.md`](docs/horizon-format-migration.md) — whether a task built
  for Bespoke Labs' separate "Horizon" platform can be migrated to run under plain Harbor
  (yes, verified — see `~/Work/ventuno-labs/horizon-test/`).
- [`docs/harbor-commands.md`](docs/harbor-commands.md) — command cheatsheet (running `nop`/
  `oracle`/a real agent, browsing results, agent requirements/costs).
- [`docs/fixture-and-scheduler.md`](docs/fixture-and-scheduler.md) — the Yoga & You synthetic
  tenant, the scheduler-sweep live-vs-baked decision, and a real `docker commit`/`VOLUME` gotcha
  that broke the first bake attempt.

## Architecture

Four services, orchestrated by `world/docker-compose.yaml`:

| Service | Role |
|---|---|
| `main` (image `channelforge-world-app`) | ChannelForge API (`apps/api`) with a **writable** source tree. `pip install -e .` + an explicit `restart-api` verb — no `--reload` file-watcher, so a restart is a deliberate, observable action (matching the legacy `ventuno-world` PHP precedent: edit, then restart). Named `main`, not `app` — Harbor's own compose overlays require that exact service name (see `docs/harbor-install.md`). |
| `postgres` (image `channelforge-world-db`) | A blank baseline by default. A separate baked variant, `channelforge-world-db:yoga-and-you`, carries the seeded "Yoga & You" synthetic tenant — see `docs/fixture-and-scheduler.md`. Not per-task yet (not needed until a task requires DB state/schema changes as part of its fix). |
| `redis` (stock `redis:7`) | Unmodified. |
| `scheduler` | Same image as `main`, running `app.jobs.scheduler` instead of the API — ChannelForge's real background reconciliation loop, run live rather than faked. Safe by construction: its network-touching sweeps all require `channel.state == "running"`, which nothing in this world (no live playout-worker) ever reaches. See `docs/fixture-and-scheduler.md`. |

**Task variation is a source patch, baked in at build time — not a shared image, not a DB
snapshot.** Harbor has no runtime "setup hook"; each task has its own `environment/Dockerfile`
that builds from the pristine vendored source and applies that task's `setup/regression.patch`
(the bug or missing behavior) as a build step. `solution/solve.sh` holds the reference fix (it
reverses that same patch, at runtime, inside the built container), used only to validate the task
is solvable (the Oracle) — it is never shown to the agent.

**Write boundary:** the agent's write access is scoped to ChannelForge's application source only.
It does **not** get write access to infra files (`world/*/Dockerfile`, `docker-compose.yaml`) or to
the test suite the verifier runs — both are reward-hacking vectors (weakening the checks instead of
fixing the bug) and are kept outside the agent's writable/visible path.

## Source vendoring

This repo doesn't vendor ChannelForge's source directly — it's pinned by commit SHA in
`PINNED_COMMIT` and pulled in on demand:

```
scripts/vendor-source.sh
```

pulls `apps/api` and `packages` from the local `../channelforge` checkout at that pinned commit into
`vendor/` (gitignored — regenerate, don't commit). Override the source path with
`CHANNELFORGE_REPO=/path/to/channelforge`.

## Local dev loop

See [`docs/setup.md`](docs/setup.md) for the full walkthrough (prerequisites, booting the world,
working inside a container, troubleshooting). Short version:

```
scripts/vendor-source.sh
cd world && docker compose up -d --build
docker compose exec main bash          # agent's shell, in miniature
```

## Tasks

- [`tasks/task-01-rights-window-bugfix`](tasks/task-01-rights-window-bugfix/) — first task,
  end-to-end proof of the model (bugfix, real injected regression, real test suite as verifier).
  Build and validate this one before authoring more.

See [`docs/workflow.md`](docs/workflow.md) for how to author the next one.

## Status

- task-01 is fully validated through real Harbor (0.22.0): `harbor run -a oracle` scores
  `task_success: 1.0`; `harbor run -a nop` scores `task_success: 0.0`. See
  [`docs/harbor-install.md`](docs/harbor-install.md) for exact commands.
- The "Yoga & You" synthetic tenant is built and baked (`channelforge-world-db:yoga-and-you`):
  30 assets, 6 collections, 1 published schedule (113 events), 58 as-run entries — verified through
  the real API, not just raw SQL. The scheduler now runs live (its own compose service) rather than
  having its output faked. See `docs/fixture-and-scheduler.md`.
- No per-task DB fixture/anomaly baking yet — the mechanism above is proven, just not required by
  task-01 (its verifier is the existing pytest suite, not live Postgres state) or wired per-task.

## Known gaps

- **`network_mode = "no-network"` is not yet enforced.** The local Docker environment provider
  rejects it without an egress-control sidecar that isn't wired up — task-01 currently runs with
  `network_mode = "public"`. See `docs/harbor-install.md` "Known gaps". Real, open item — not
  cosmetic — even though nothing in task-01 currently makes an outbound call.
