# Building the ChannelForge World single Docker image

Audience: the DevOps engineer building the distributable artifact. This doc is self-contained —
it does not assume you already have any of the source repos checked out, or that you're working
from inside any particular orchestration repo's directory tree. Every path below is either an
explicit `git clone` + pinned commit, or an asset that this doc names by its own repo + path.

## 0. The four repos and their pins

| Repo | URL | Pinned commit | Role |
|---|---|---|---|
| ChannelForge | `https://github.com/subbu-murugan/channelforge.git` | `b46733b45c719aa5cb111c89ba5d50f25989a0ff` | Schedule + playout API (`apps/api`) **and** its own operator web frontend (`apps/web`) |
| ssaiadserver | `https://github.com/subbu-murugan/ssaiadserver.git` | `f9e20b71c466926c653a371f1d2c493de5140caf` | SSAI ad server: control-plane + data-plane |
| fast-world-tv | `https://github.com/subbu-murugan/fast-world-tv.git` | `61b73c12b3a0f64327007046ef5891559d32ae24` | Public FAST viewer (Next.js) |
| channelforge-world | `https://github.com/arun-mukkath-ventuno/channelforge-world.git` | `28761787fea30a32e177f8bf2378b9dfb7a4aec2` | The orchestration layer: integration glue patches, `world.conf`, image build files, eval tasks. This is where everything in §4–§6 below physically lives. |

Bump a pin only by changing the corresponding row above (and, in the orchestration repo, the
matching `PINNED_COMMIT_<SERVICE>` file) — never by tracking a moving branch. Fetch each repo
deterministically:

```bash
git clone <repo-url> <dest>
cd <dest> && git checkout <pinned-commit>
# or, without a full clone:
git archive --remote=<repo-url> <pinned-commit> | tar -x -C <dest>
```

## 1. What "the image" means here

The natural dev/CI topology is one container per service (a ChannelForge API, a ChannelForge
web frontend, a scheduler, ssai-control, ssai-data, fast-web, plus Postgres ×2 and Redis ×2 —
10 containers). That's the right shape for local development. It is **not** the shape of the
distributable artifact.

The distributable artifact is **one image**, modeled on the packaging pattern of a prior
single-image world built by this same team:
`us-central1-docker.pkg.dev/apex-485220/polara-ventuno/ventuno-world:0.2.0`
(`sha256:508b2d66087d1046c36dae895ce186efed35cc072ed878b0b8a3fc643d438b0c`). That image's own
tech stack (PHP/Apache/MySQL/Solr/RabbitMQ, an entirely different product) has nothing in
common with ChannelForge World's (Python/Node/Next.js/React) — it is cited for its **packaging
pattern only**, not as a code or architecture reference:

- `supervisord` as PID 1.
- Every process — data stores included — is a `[program:...]` block in one `.conf` file, not a
  separate container.
- `priority=` orders startup into tiers (stores first, gated app services next, dependents last).
- Hard dependencies are gated with a `wait-for-*.sh` wrapper around the real command.
- Everything talks over `127.0.0.1:<port>`, not container/service DNS names.
- Optional/on-demand pieces are a `[group:...]` left stopped by default.

§4 below is the full worked mapping of that pattern onto all 10 ChannelForge World services.

## 2. Scope correction: the ChannelForge frontend is part of the bundle

An earlier draft of this doc only covered the ChannelForge **API**. That was incomplete.
ChannelForge ships two apps, both under the ChannelForge repo pinned above:

- `apps/api` — the FastAPI control plane (Python 3.12).
- `apps/web` — a Vite/React 18 SPA (`channelforge-web`), the operator UI. Its own
  `apps/web/Dockerfile` states the intended production shape directly: *"Production build is
  served behind nginx"* — i.e. `npm run build` to static assets, then served, not `vite dev`.
  In dev it proxies `/api`, `/health`, and `/hls` to the API and to nginx (see
  `apps/web/vite.config.ts`); in the single image, that proxying job moves to a static file
  server / nginx layer serving the built assets and reverse-proxying those same three path
  prefixes to `127.0.0.1:8000` (API) and wherever HLS is served (see §4's note on the HLS gap).

So the bundle is **10 processes**, not 8: ChannelForge API, ChannelForge web (built + served
statically), ChannelForge scheduler, ChannelForge's Postgres + Redis, ssai-control, ssai-data,
ssaiadserver's Postgres + Redis, fast-web.

## 3. Prerequisites

- Docker with BuildKit (`docker buildx`), amd64 build capability. Build on Apple Silicon with
  `--platform linux/amd64` (or a remote amd64 builder) — cross-arch local runs work under
  emulation for inspection but are not a substitute for an amd64 validation build.
- Registry auth for wherever this gets pushed (mirror `ventuno-world`'s registry:
  `us-central1-docker.pkg.dev/apex-485220/polara-ventuno/`, or a project-specific path — confirm
  the exact path with the team before the first push).
- Read access to the 3 pinned application repos in §0, at those exact commits.
- The orchestration repo (`channelforge-world`, §0) checked out at its pinned commit — it holds
  the two integration glue patches, the eval tasks, and (once built per this doc) the
  `world/image/` build files themselves.

## 4. Architecture: the supervisord layout

### Port map (127.0.0.1, no container/service DNS names)

| Service | Source | Loopback port |
|---|---|---|
| ChannelForge Postgres | — | `5432` |
| ChannelForge Redis | — | `6379` |
| ChannelForge API | `channelforge/apps/api` | `8000` |
| ChannelForge web (built, served statically) | `channelforge/apps/web` | `5173` (internal only — see nginx note below) |
| ChannelForge scheduler | `channelforge/apps/api` (`python -m app.jobs.scheduler`) | — (no port) |
| ssaiadserver Postgres | — | `5433` (5432 taken) |
| ssaiadserver Redis | — | `6380` (6379 taken) |
| ssai-control | `ssaiadserver` | `4000` |
| ssai-data | `ssaiadserver` | `4010` |
| fast-web | `fast-world-tv` | `3000` |
| **nginx (front door)** | new, this doc | `80` — externally exposed; serves the built ChannelForge web SPA and reverse-proxies `/api`, `/health` → `127.0.0.1:8000` (mirrors `apps/web/vite.config.ts`'s dev-time proxy map, moved to nginx for production) |

Every env var that today points at a compose/container hostname (`DATABASE_URL`, `REDIS_URL`,
`CF_ORIGIN_BASE_URL`, `CF_SSAI_ADSERVER_BASE_URL`, `CHANNELFORGE_ORIGIN_URL`,
`DATA_PLANE_PUBLIC_URL`, `CONTROL_PLANE_URL`, `FAST_HLS_10x`, `VITE_API_PROXY`, `VITE_HLS_PROXY`)
gets rewritten to `http://127.0.0.1:<port>` per this table — a mechanical rewrite, no
application code changes, since every one of these was already externalized as an env var.

### Startup tiers (priority=)

```
10  postgres, redis, ssai-postgres, ssai-redis          # stores, no dependencies
20  main (ChannelForge API)      -- gated: wait-for.sh 127.0.0.1:5432 127.0.0.1:6379
20  ssai-control                  -- gated: wait-for.sh 127.0.0.1:5433 127.0.0.1:6380
25  scheduler                     -- gated: same as main
25  ssai-data                     -- gated: wait-for.sh 127.0.0.1:4000 127.0.0.1:8000
30  fast-web                      -- gated: wait-for.sh 127.0.0.1:4010
30  nginx (front door + built ChannelForge web SPA) -- gated: wait-for.sh 127.0.0.1:8000
```

Same tiering approach `ventuno-world`'s `world.conf` uses (stores at priority 10, gated app
services next, dependent frontends last) — the pattern is cited, not the content.

### Gating script

```bash
#!/usr/bin/env bash
# wait-for.sh <host:port> [<host:port> ...] -- <command...>
set -euo pipefail
while [[ "$1" != "--" ]]; do
  hostport="$1"; shift
  until (echo > "/dev/tcp/${hostport%%:*}/${hostport##*:}") 2>/dev/null; do sleep 1; done
done
shift
exec "$@"
```

### Postgres and Redis as supervised processes, not base images

Both Postgres instances and both Redis instances get installed into the shared image filesystem
(`postgresql-16`, `redis-server`) and run as `[program:]` blocks on the loopback ports above,
rather than pulled as separate `postgres`/`redis` container images. Each `PGDATA` stays off any
Docker-`VOLUME`-declared path — `docker commit`/image-layer capture never sees inside a declared
volume, which matters doubly once §6's baked sample data depends on that same layer-capture
mechanism.

### Restart verbs

The three existing agent-facing restart scripts (ChannelForge API, ssaiadserver, fast-web —
maintained in the orchestration repo's `scripts/`) don't change: they're already daemon-agnostic
PID-file scripts. They become the `command=` of their `[program:]` blocks; `autorestart=true`
replaces their current "loop forever in `--foreground` mode" duty. A new fourth restart verb
covers the ChannelForge web frontend (rebuild the Vite SPA + tell nginx to pick up the new static
assets — `nginx -s reload` is sufficient, no process restart needed since nginx just serves files
off disk).

## 5. Build pipeline

Multi-stage Dockerfile (maintained in the orchestration repo as `world/image/Dockerfile`):

1. **Fetch stage** — `git archive` (or clone+checkout) each of the 3 application repos at the
   pinned commits in §0.
2. **ChannelForge API stage** — copy `apps/api` + `packages`, apply the
   `channelforge-ssai-base-url.patch` glue patch (adds `CF_SSAI_ADSERVER_BASE_URL` wiring —
   maintained in the orchestration repo's `world/patches/`), `pip install`.
3. **ChannelForge web stage** — copy `apps/web`, `npm install`, `npm run build` → static assets
   in `apps/web/dist`. No patch needed — the SPA already reads its API base URL from env at
   build/serve time.
4. **ssaiadserver stage** — copy all packages, apply `ssaiadserver-manifest-template.patch`
   (adds `CHANNELFORGE_MANIFEST_PATH_TEMPLATE` — also in `world/patches/`), `npm install && npm
   run build`. One built tree serves both `ssai-control` and `ssai-data` (`SSAI_SERVICE` env var
   selects at runtime).
5. **fast-world-tv stage** — `pnpm install --frozen-lockfile && pnpm build`.
6. **Sample-data stage** — see §6.
7. **Final stage** — base image with Python 3.12, Node 22, `patch`, `bash`, `postgresql-16`,
   `redis-server`, `nginx`, `supervisor` all present. `COPY --from=` each built tree, the two
   Postgres data directories (§6), the nginx config serving the ChannelForge web `dist/` and
   reverse-proxying `/api`+`/health`, the restart scripts, `wait-for.sh`, and `world.conf` to
   `/etc/supervisor/conf.d/`. `EXPOSE 80 4000 4010 3000` (everything else stays loopback-only).
   `CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]`.

Expect this image to be large — a single base with 3 language runtimes plus 2 databases is
comparable in kind to `ventuno-world:0.2.0`'s 8.9GB (PHP+Node+MySQL+Solr+RabbitMQ); a similar
order of magnitude here is expected, not a build mistake.

## 6. Baked sample data (future work, scope this in now)

The orchestration repo already has a working, smaller-scale version of this: `scripts/
bake-fixture-db.sh` boots a throwaway stack, runs migrations, runs `scripts/seed_fixture.py`
(the "Yoga & You" fixture), then `docker commit`s the seeded Postgres *container* into a
standalone tagged image (`channelforge-world-db:yoga-and-you`) — reset becomes "recreate from
that image," not "run a seed script at trial time."

For the single image, this folds directly into the multi-stage build instead of a post-hoc
`docker commit`: add a **sample-data stage** that starts Postgres transiently inside the build
(`initdb`, start, `alembic upgrade head`, run the seed script, stop cleanly), and the final stage
`COPY --from=` that stage's populated `PGDATA` directory straight into the image layer — the same
off-VOLUME-path `PGDATA` location already required for `docker commit` capture (§4) makes this
work as a plain Dockerfile `COPY` too, no `docker commit` step needed at all. This is a genuine
increase in scope from the current fixture (which is ChannelForge-only) once "derived sample
data" needs to span ssaiadserver's Postgres as well — plan for a second such stage
(`ssai-sample-data`) seeding `ssai-postgres`'s `PGDATA` the same way, gated on ssaiadserver's own
migrations (`vendor/ssaiadserver/migrations` in the orchestration repo, or fetched directly from
the ssaiadserver repo per §0).

This section is intentionally a plan, not a finished pipeline — "derived sample data" (exact
shape, source, and whether it spans both databases or just ChannelForge's) is still to be
specified; revise this section once that's decided rather than treating it as build-ready today.

## 7. Versioning & tagging

Mirror `ventuno-world`'s scheme: semver tag on the image (`channelforge-world:0.1.0`), bumped on:

- any pinned-commit change in §0 (patch bump for a routine re-pin; minor if it required
  re-validating an eval task)
- any glue-patch change in `world/patches/` (minor — integration contract shift)
- any new/changed eval task (minor)
- any baked sample-data change (minor — changes what a reset stack contains)
- any packaging-only change to `world/image/`/`world.conf` with no behavior change (patch)

The commit table in §0 remains the real provenance record for "what code is in this tag"; the
image tag is a convenience pointer, not a substitute — carry both in release notes.

## 8. Push to the registry

```bash
docker buildx build --platform linux/amd64 \
  -f world/image/Dockerfile \
  -t <registry-path>/channelforge-world:<version> \
  --push .
```

Confirm `<registry-path>` and tag-immutability policy with the team before the first push —
once an eval task has been validated against a given tag and shared externally, that tag must
not be silently overwritten.

## 9. Pre-publish validation gate

1. `docker run` the built image standalone; `supervisorctl status` shows all 10 `[program:]`
   entries `RUNNING` together (joint boot, not tested individually).
2. From outside the container: `:80/` serves the ChannelForge web SPA and `:80/api/...` reaches
   the API through nginx; `:4000/v1/channels`; `:4010`; `:3000/api/fast/channels`.
3. Run every eval task's Harbor validation (`harbor run -a oracle` → `task_success: 1.0`,
   `harbor run -a nop` → `0.0`) against the new image tag — a packaging-only change still needs
   this, since the point is proving packaging didn't break anything.
4. `docker history`/`dive` the final image — confirm no eval task's hidden-verifier content
   (`tests/`, `solution/`) leaked into a layer.
5. If §6 sample data is in scope for this tag: confirm a fresh container boots with the seeded
   data present and queryable (not just that the build succeeded).

## 10. Rollback

Tags are immutable once published (§8) — rollback means pointing consumers at the previous tag,
never re-pushing over an existing one. Keep at least the last 3 tagged versions in the registry.

## 11. Troubleshooting appendix

- **A `[program:]` won't start**: `supervisorctl status`, then
  `/var/log/supervisor/<program>.err.log` inside the container.
- **`patch: command not found` / `bash: command not found`**: both already-hit issues on Alpine/
  slim base images in this project's history — the final stage needs both installed explicitly.
- **Two Postgres / two Redis instances on one loopback**: they can't share default ports — this
  is why §4 moves `ssai-postgres`/`ssai-redis` to `5433`/`6380`.
- **`wait-for.sh` gate never releases**: usually a leftover container/compose-DNS hostname in an
  env var that §4's port-map rewrite missed — grep the final `world.conf` for any bare hostname.
- **nginx serves a stale SPA build**: the ChannelForge web restart verb must rebuild
  (`npm run build`) before `nginx -s reload`, not just reload — reload alone re-reads nginx
  config, not the static files it's pointed at (which don't change path, only content).
- **Baked sample data missing after a fresh `docker run`**: check `PGDATA` wasn't accidentally
  left on a path Docker treats as a `VOLUME` in the final stage's base image — same failure mode
  already documented for the compose-world fixture bake.
- **Cross-arch build on Apple Silicon**: always pass `--platform linux/amd64` for the real build;
  an unqualified local run under emulation is for inspection only.

## 12. Reference: ventuno-world:0.2.0's packaging pattern, annotated

Retrieved by inspecting the image loaded in Docker Desktop
(`sha256:508b2d66087d1046c36dae895ce186efed35cc072ed878b0b8a3fc643d438b0c`,
`us-central1-docker.pkg.dev/apex-485220/polara-ventuno/ventuno-world:0.2.0`):

```bash
docker inspect <digest>
docker run --rm --entrypoint cat <image> /etc/supervisor/supervisord.conf
docker run --rm --entrypoint sh <image> -c "cat /etc/supervisor/conf.d/*.conf"
```

Structure (a completely different product — PHP/Apache/MySQL/Solr/RabbitMQ — the pattern is
what's being cited, not the content):

- `[supervisord]`: `nodaemon=true`, root, one logfile.
- Tier 10: `mysql` (`mysqld_safe`), `memcached` — no dependencies.
- Tier 15: `solr`, `cdn` (nginx), `mailpit`.
- Tier 20: `apache` — gated by a `wait-for-mysql.sh` wrapper.
- Tier 25: `ottweb` (Node SSR) — after `apache`.
- Tier 30: `[group:crons]` — four `supercronic` cron programs, autostarted.
- Tier 40–50: `[group:start-upload]` (RabbitMQ + a Python worker) and a Node `builder` — present
  and autostarted in this particular build, but structurally the "optional pipeline" slot to
  reuse later for anything we want off-by-default (e.g. a future `playout-worker`/object-storage
  tier — tracked as a known gap in the orchestration repo's `docs/ecosystem.md`).
- Every inter-service URL in every `environment=` line is `127.0.0.1:<port>` — confirms this
  doc's port-map approach (§4) is the established pattern, not invented for this doc.
