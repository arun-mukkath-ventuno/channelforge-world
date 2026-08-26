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
2. **No auto-reload, ever.** Restarts happen only via the explicit `restart-api` verb. Do not
   reintroduce `uvicorn --reload` or any other file-watcher — the deliberate-restart step is part
   of what's being evaluated, not an implementation inconvenience to smooth over.
3. **Determinism over convenience.** `PINNED_COMMIT` names an exact ChannelForge SHA — never point
   `scripts/vendor-source.sh` at a moving branch. A task's `setup/regression.patch` must produce
   byte-identical starting state every time it's applied to pristine vendored source. If a change
   here would make two runs of the same task diverge, don't make it.
4. **The app/db images stay pristine and task-agnostic.** No task-specific bug, fixture, or config
   belongs baked into `world/app/Dockerfile` or `world/db/Dockerfile`. Task-specific state is
   applied by that task's own `setup/apply.sh`, after the container is already running.
5. **No live external network egress**, ever, from anything running inside the world. No real
   YouTube, no real RTMP/third-party ingest. If a task needs network-shaped behavior, it talks to a
   local stub inside the sealed world, never out to the internet.
6. **The Oracle and the verifier are never shown to, and never writable by, the evaluated agent.**
   `solution/solve.sh` exists to validate a task is solvable, not as a hint. `tests/test.sh` and
   whatever test files it runs are the ground truth — if the agent can read or edit them, the task
   is broken, not just weaker.

## Architecture rules

- Three images: `channelforge-world-app` (writable ChannelForge source, `pip install -e .` +
  `restart-api`), `channelforge-world-db` (Postgres, currently a stock baseline), `redis:7` (stock,
  unmodified). No `supervisord` — orchestration is `docker-compose`, not a single monolithic image.
- Source is vendored, not committed: `scripts/vendor-source.sh` pulls `apps/api` + `packages` from
  the real ChannelForge repo at `PINNED_COMMIT` into `vendor/` (gitignored, regenerate on demand).
- A task's variation is a source patch (`setup/regression.patch` + `setup/apply.sh`), not a
  separate DB image tag — this is what lets one pristine app image serve arbitrarily many future
  tasks without a rebuild per task. DB-state variation is provisioned (Alembic reachable, DDL
  rights) but not required until a task actually needs it.

## Testing requirements — before a task counts as built

- The setup patch applies cleanly, with no fuzz, to a freshly-vendored pristine checkout.
- Applying it breaks exactly the intended test(s) — not more, not fewer than expected.
- Reversing it (the Oracle) restores a byte-identical original, and the real test suite passes in
  full.
- A no-op run (agent does nothing) fails the verifier.
- The full loop has been run against a live `docker compose` world at least once: healthy → bug
  injected → verifier fails → fix applied + `restart-api` → container survives the restart, service
  healthy → verifier passes.

## Definition of done for a new task

- `instruction.md` reads as a real bug report or feature request — no file names, function names,
  or hints at the fix.
- `task.toml`, `setup/`, `solution/solve.sh`, `tests/test.sh`, and `environment/` all exist and
  follow the shape in `docs/workflow.md`.
- All items under "Testing requirements" above pass.
- Anything not yet validated against the real `harbor` CLI is stated as such, not implied to work.
