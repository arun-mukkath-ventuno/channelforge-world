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

## Architecture

Three images, orchestrated by `world/docker-compose.yaml`:

| Image | Role |
|---|---|
| `channelforge-world-app` | ChannelForge API (`apps/api`) with a **writable** source tree. `pip install -e .` + an explicit `restart-api` verb — no `--reload` file-watcher, so a restart is a deliberate, observable action (matching the legacy `ventuno-world` PHP precedent: edit, then restart). |
| `channelforge-world-db` | Postgres. One baseline image for the POC — no per-task DB snapshots yet (not needed until a task requires DB state/schema changes as part of its fix; see Known limitations below). Alembic runs against it for real, so that capability is proven even though no POC task exercises it yet. |
| `redis` (stock `redis:7`) | Unmodified. |

**Task variation is a source patch, not a DB snapshot.** The app image itself is pristine and
task-agnostic (plain vendored ChannelForge source, no bugs baked in). Each task directory carries a
`setup/regression.patch` (the bug or missing behavior) plus a `setup/apply.sh` that applies it
inside the running container *before* the agent's turn starts — that's what makes a shared app
image serve many different tasks without a rebuild per task. `solution/solve.sh` holds the
reference fix, used only to validate the task is solvable (the Oracle) — it is never shown to the
agent.

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
docker compose exec app bash          # agent's shell, in miniature
```

## Tasks

- [`tasks/task-01-rights-window-bugfix`](tasks/task-01-rights-window-bugfix/) — first task,
  end-to-end proof of the model (bugfix, real injected regression, real test suite as verifier).
  Build and validate this one before authoring more.

See [`docs/workflow.md`](docs/workflow.md) for how to author the next one.

## Known limitations (POC)

- No per-task DB fixture/anomaly baking yet — provisioned (Alembic reachable, DB user has DDL
  rights) but not exercised. First task that actually needs it should be the forcing function for
  building the fixture baker.
- `channelforge-world-db` is not yet seeded with a synthetic tenant ("Yoga & You") — not required
  for task-01, since its verifier is the existing pytest suite (SQLite-backed test fixtures), not
  live Postgres state.
- `task.toml` fields are a best-effort draft against Harbor's documented schema — validate against
  the actual `harbor` CLI before the first real `harbor run`, in particular the `[task.setup]`
  hook that applies `setup/regression.patch` (mechanism/field name unconfirmed).
- task-01's full loop has been manually validated against the real `docker compose` world
  (healthy → bug injected → verifier fails → hand-simulated fix + `restart-api` → container
  survives the restart, service healthy → verifier passes) — but not yet run through the actual
  `harbor` CLI, so the `task.toml`/`[task.setup]` wiring itself is still unconfirmed.
