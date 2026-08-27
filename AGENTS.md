# AGENTS.md — Implementation guardrails for channelforge-world

This file governs how automated coding agents (and humans) build and extend this repo. It does
**not** govern the agent being evaluated inside a task — that agent only ever sees a task's
`instruction.md`. See [`docs/workflow.md`](docs/workflow.md) for the full task-authoring workflow
and [`docs/setup.md`](docs/setup.md) for local setup.

## Prime directives

1. **Write boundary is load-bearing, not incidental.** The evaluated agent's write access is
   scoped to the vendored ChannelForge application source only. Never grant it (or wire a task
   such that it effectively gets) write access to `world/*/Dockerfile`, `world/docker-compose.yaml`,
   a task's `environment/`, `tests/`, or `solution/` — each is a reward-hacking vector (weaken the
   checks, or edit the test instead of fixing the bug, instead of editing the tests directory).
2. **No auto-reload, ever, and exactly one restart command — never a multi-step alternative the
   agent could fall back to.** Restarts happen only via the explicit `restart-api` verb. Do not
   reintroduce `uvicorn --reload` or any other file-watcher — the deliberate-restart step is part
   of what's being evaluated, not an implementation inconvenience to smooth over. This is validated,
   not just theoretical: a migrated Horizon task (`docs/horizon-format-migration.md`) failed a real
   agent run because its environment offered no single canonical restart command — the agent's
   reasonable fallback (`service apache2 restart`) started a process outside supervisord's control
   that later collided with the verifier's own startup. `restart-api` existing as one script with
   no second code path is exactly what prevents that class of failure here.
3. **Determinism over convenience.** `PINNED_COMMIT` names an exact ChannelForge SHA — never point
   `scripts/vendor-source.sh` at a moving branch. A task's `setup/regression.patch` must produce
   byte-identical starting state every time it's applied to pristine vendored source. If a change
   here would make two runs of the same task diverge, don't make it.
4. **The shared `world/app/Dockerfile` and `world/db/Dockerfile` stay pristine and task-agnostic.**
   No task-specific bug, fixture, or config belongs in them. A task's bug/gap belongs in that
   task's own `environment/Dockerfile`, baked in at build time (`RUN patch -p1 < ...`) — Harbor has
   no runtime "setup hook"; the environment a task gets is exactly what its own Dockerfile builds.
5. **No live external network egress**, ever, from anything running inside the world. No real
   YouTube, no real RTMP/third-party ingest. If a task needs network-shaped behavior, it talks to a
   local stub inside the sealed world, never out to the internet.
6. **The Oracle and the verifier are never shown to, and never writable by, the evaluated agent.**
   `solution/solve.sh` exists to validate a task is solvable, not as a hint. `tests/test.sh` and
   whatever test files it runs are the ground truth — if the agent can read or edit them, the task
   is broken, not just weaker.

## Architecture rules

- Compose service naming is not cosmetic: the agent's primary container **must** be named `main`.
  Harbor's own base/build/no-network compose overlays all target a service called `main`
  (`harbor.constants.MAIN_SERVICE_NAME`) — a different name silently fails to wire the agent up
  correctly. `world/docker-compose.yaml` and every task's `environment/docker-compose.yaml` use
  `main` for this reason.
- Four services: `main` (writable ChannelForge source, `pip install -e .` + `restart-api`),
  `postgres`, `redis:7` (stock, unmodified), `scheduler` (same image as `main`, running
  `app.jobs.scheduler` live — see `docs/fixture-and-scheduler.md` for why that's safe here). No
  `supervisord` — orchestration is `docker-compose`, not a single monolithic image.
- `world/db/Dockerfile` sets `ENV PGDATA=/var/lib/postgresql/cf-data` deliberately. The base
  `postgres:16` image declares `/var/lib/postgresql/data` as a `VOLUME`, and `docker commit` never
  captures data inside a declared volume — moving `PGDATA` off that path is what makes baking a
  seeded Postgres image (`scripts/bake-fixture-db.sh`) actually work. Do not move `PGDATA` back
  without re-verifying a baked image boots with data intact.
- Source is vendored, not committed: `scripts/vendor-source.sh` pulls `apps/api` + `packages` from
  the real ChannelForge repo at `PINNED_COMMIT` into `vendor/` (gitignored, regenerate on demand).
- A task's variation is a source patch (`setup/regression.patch`) baked into that task's own
  `environment/Dockerfile` at build time — not a shared app image, not a separate DB image tag.
  DB-state variation is provisioned (Alembic reachable, DDL rights) but not required until a task
  actually needs it.
- **Known gap:** `network_mode = "no-network"` is not yet enforced under the local Docker
  environment provider (it needs an egress-control sidecar not yet wired up) — see
  `docs/harbor-install.md`. Don't claim network isolation as a guarantee until this is closed.

## Testing requirements — before a task counts as built

- The regression patch applies cleanly, with no fuzz, to a freshly-vendored pristine checkout.
- Applying it breaks exactly the intended test(s) — not more, not fewer than expected.
- Reversing it (the Oracle) restores a byte-identical original, and the real test suite passes in
  full.
- Validated through **real Harbor**, not a hand-simulated substitute:
  `harbor run -a oracle` scores `task_success: 1`, and `harbor run -a nop` scores
  `task_success: 0`. See `docs/harbor-install.md` for exact commands.

## Definition of done for a new task

- `instruction.md` reads as a real bug report or feature request — no file names, function names,
  or hints at the fix.
- `task.toml` (verified against a fresh `harbor init` scaffold, not copied from an older task),
  `setup/regression.patch`, `environment/Dockerfile`, `environment/docker-compose.yaml` (service
  named `main`), `solution/solve.sh`, and `tests/test.sh` all exist and follow the shape in
  `docs/workflow.md`.
- All items under "Testing requirements" above pass — including the real `harbor run` checks, not
  just a manual simulation.
