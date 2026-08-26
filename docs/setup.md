# Setup

## Prerequisites

- Docker Desktop (or another local Docker daemon) with `docker compose` v2.
- A local checkout of [`channelforge`](https://github.com/subbu-murugan/channelforge) as a sibling
  directory (`../channelforge` relative to this repo), or set `CHANNELFORGE_REPO` to point
  elsewhere. It must be a real git checkout — `scripts/vendor-source.sh` uses `git archive`, not a
  plain file copy.
- Python 3.12+ locally only if you want to run `pytest` outside a container (optional — the
  container has everything it needs).

## First-time setup

```
scripts/vendor-source.sh
```

This pulls `apps/api` and `packages` from `../channelforge` at the commit pinned in
`PINNED_COMMIT` into `vendor/` (gitignored — it's a derived artifact, regenerate it, don't hand-edit
it or commit it). Re-run this any time `PINNED_COMMIT` changes.

## Boot the world

```
cd world
docker compose build
docker compose up -d
docker compose ps        # all three services should be healthy/running
```

`app` is reachable at `localhost:8000` (FastAPI's `/docs` is a quick health check).

## Working inside the world (what an agent's turn looks like)

```
docker compose exec app bash
```

From inside:
- Source lives at `/app` (this is ChannelForge's real `apps/api`, vendored at the pinned commit).
- Edit files normally.
- If you changed dependencies: `pip install -e .` (or `-e ".[dev]"` for dev/test deps).
- `restart-api` — stops the running `uvicorn`, starts a new one. This is the *only* way a code
  change takes effect; there is no file-watcher.
- `pytest tests/<file>.py` runs the real test suite from inside the container.

## Running a task's setup patch manually (before Harbor wiring exists)

```
docker cp tasks/task-01-rights-window-bugfix/setup/regression.patch <app-container>:/tmp/regression.patch
docker compose -f world/docker-compose.yaml exec app bash -c "cd /app && patch -p1 < /tmp/regression.patch"
```

Then, as if you were the evaluated agent: edit the code, `restart-api`, and run that task's
`tests/test.sh` (copy it in the same way) to check your fix.

## Tearing down / resetting

```
docker compose down        # stop and remove containers, keep images
docker compose down -v     # also drop volumes (only matters once the db image holds real data)
```

Reset for a fresh trial = `down` then `up` again — containers are recreated from the same images,
so this is the whole determinism story once `vendor/` and the images themselves haven't changed.

## Troubleshooting

- **`patch: command not found` inside `app`** — rebuild; `patch` is installed in
  `world/app/Dockerfile`. If you're on an older image, `docker compose build app`.
- **Container exits right after an agent-triggered `restart-api`** — this was a real bug found
  during initial validation (PID 1 was `wait`-ing on the original `uvicorn` pid). If you see it
  again, check `scripts/restart-api.sh`'s foreground branch hasn't regressed back to a direct
  `wait "$(cat "$PIDFILE")"`.
- **`vendor-source.sh` fails with "not a git checkout"** — `CHANNELFORGE_REPO` needs to point at an
  actual `.git` checkout, not an extracted archive/zip.
