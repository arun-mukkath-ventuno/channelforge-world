# Harbor installation

## Setup

channelforge-world uses its own isolated venv — do not reuse a shared/system Harbor install, and
don't assume any other Harbor install on the machine has the same schema version (see "Version
matters" below).

```
python3 -m venv .venv
source .venv/bin/activate
pip install harbor
harbor --version
```

This installed **0.22.0** (latest on PyPI at the time of writing). No `harbor auth login` is
needed for local runs (`--env docker`) with a built-in agent (`oracle`, `nop`) — auth is only for
`--upload`/Harbor Hub sharing.

## Version matters — schema drifted between releases

While setting this up, an older Harbor install (0.6.1, in a machine-wide venv shared with an
unrelated sibling project) was found and initially used to draft `task.toml`. Its `harbor init`
produces `schema_version = "1.2"` with materially different fields (`allow_internet: bool` instead
of `network_mode`, no `[task] version`, resource limits directly under `[environment]`). The
current 0.22.0 install produces `schema_version = "1.4"`. **Don't assume a docs page or an older
task.toml you find is current — regenerate a scaffold with `harbor init` and diff against it.**

## Validating a task without writing prose about it

These commands actually build and run the thing — prefer them over reading source when in doubt:

```
harbor init --task <org>/<name> -o <dir>       # scaffold a real, current task.toml + templates
harbor task start-env -p <task-dir> -i         # build the environment, drop into a shell in it
harbor run -p <task-dir> -a oracle -e docker -y --jobs-dir /tmp/jobs   # run the Oracle for real
harbor run -p <task-dir> -a nop -e docker -y --jobs-dir /tmp/jobs      # confirm no-op fails
harbor view /tmp/jobs                          # browse trial results/trajectories
```

`-a oracle` runs `solution/solve.sh` as if it were the agent — this is the real way to validate a
task's Oracle, not a hand-simulated substitute. `-a nop` does nothing, and should always score 0.

## What we learned building task-01 that corrected earlier assumptions

- **The agent's primary compose service must be named exactly `main`.** Harbor's own base/build/
  no-network compose overlays all target a service called `main` (`harbor.constants.
  MAIN_SERVICE_NAME`). The world's `docker-compose.yaml` originally used `app` — renamed.
- **There is no `[task.setup]` runtime hook.** A task's environment is fully defined by what its
  own `environment/Dockerfile` (or `environment/docker-compose.yaml`) builds — nothing analogous
  to a "run this script before the agent's turn starts" field exists in `TaskConfig`. task-01's
  regression is now baked into `environment/Dockerfile` at build time (`RUN patch -p1 < ...`), not
  applied by a `setup/apply.sh` script at container start (that file has been removed).
- **`network_mode = "no-network"` is not supported by the local `docker` environment provider
  out of the box.** It requires an egress-control sidecar (`cap_add: [NET_ADMIN, NET_RAW]`) that
  isn't wired up yet. `harbor run` raises `ValueError: network_mode='no-network' is not supported
  by EnvironmentType.DOCKER environment` if you ask for it without that sidecar. task-01 currently
  runs with `network_mode = "public"` as a result — **this is a real, open gap** against the "no
  live network egress" guarantee the POC's design leans on, not a cosmetic one. See "Known gaps"
  below.
- **Compose service `main` gets `command: ["sh", "-c", "sleep infinity"]` from Harbor's own build
  overlay**, which overrides the image's own `CMD` when merged. In practice this didn't block
  task-01 (the built-in `oracle`/`nop` agents don't depend on `uvicorn` already running — the
  Oracle's own `solve.sh` calls `restart-api` itself, which works whether or not the process was
  already up), but it does mean **the API is not guaranteed running when an agent's turn starts**
  — don't assume it is; a task/instruction that needs a live API should have the agent (or the
  Oracle) call `restart-api` explicitly first.
- Both `reward.txt` (bare 0/1) and `reward.json` (richer sub-scores) are real, supported outputs —
  `tests/test.sh` writes both.

## Known gaps

- **No-network enforcement isn't real yet** — every task currently runs with `network_mode =
  "public"` under local Docker. task-01 doesn't make any outbound calls, so nothing is actively
  leaking, but this needs to be closed (egress-control sidecar, or switch to an environment
  provider where `no-network` is natively supported) before that's a guarantee rather than an
  accident of what the tasks happen not to do.
- Only validated under `--env docker` (local). Other providers listed by `harbor run --help`
  (daytona, e2b, modal, runloop, gke, ...) are untested against this repo.
