# ChannelForge World MVP: single-image build and distribution

> **Status: draft for team review.** This document defines the Phase 1 MVP artifact. The
> implementation under `world/image/` does not exist yet.

## 1. Goal

Build the complete ChannelForge World as one portable Linux Docker image for external teams.
The current multi-container Compose topology remains the development and integration reference;
it is not the distributable artifact.

The MVP image must:

- contain all ChannelForge, ssaiadserver, and fast-world-tv services, including the ChannelForge
  operator frontend;
- contain two PostgreSQL instances and two Redis instances;
- start every required API, worker, store, UI, origin, and stub automatically from one
  `docker run`;
- ship with deterministic sample data already loaded into both PostgreSQL databases;
- ship with local programme, ad, and slate media sufficient to produce a raw ChannelForge HLS
  stream and a separately-addressable SSAI-stitched stream;
- retain writable application source for the evaluated agent;
- require an explicit, service-specific restart command after an agent edits source;
- make no runtime request to a live external service; and
- contain no task verifier, Oracle solution, API credential, production secret, or private
  customer data.

The likely publication target is Google Artifact Registry. Registry project, repository,
authentication, retention, and external-team access are deliberately deferred until the image
works and passes the acceptance gate in this document.

This MVP decision supersedes the POC-era architecture language in `AGENTS.md` that says the world
has four services and must not use supervisord. Update those governing instructions as a separate,
reviewed change before implementing `world/image/`; documentation of the new target does not by
itself waive repository guardrails.

## 2. Source and provenance

The image is assembled from four repositories:

| Repository | Pin source | Content used |
|---|---|---|
| ChannelForge | `PINNED_COMMIT_CHANNELFORGE` | `apps/api`, `apps/web`, `packages`, `services/media-worker`, `services/playout-worker` |
| ssaiadserver | `PINNED_COMMIT_SSAIADSERVER` | packages, migrations, web assets |
| fast-world-tv | `PINNED_COMMIT_FASTWORLDTV` | Next.js viewer |
| channelforge-world | the release commit | packaging, restart scripts, fixtures, task environments |

The three application pins are files in the repository root and are the only authoritative pin
values. Do not duplicate literal SHAs in this document or the Dockerfile. A release manifest must
record all four resolved commits plus the final image digest.

**Pinning policy (as of 2026-09-11): pins track each source repo's `world` branch, not `main`.**
Each of the three source repos carries a long-lived `world` branch with blueprint/world-specific
commits (virtual clock, canonical world event envelope, seed-deterministic ids, env-driven URLs,
offline eval topology) layered on top of upstream `main`. All future POC/world-specific fixes land
on `world` directly — not as local patches in this repo. The re-pin audit below fetches and diffs
against `origin/world` (after periodically merging `main` into `world` to pull in upstream fixes),
not `origin/main`.

**Resolved 2026-09-11 (T3.1-T3.4).** `scripts/vendor-source.sh` now also vendors `apps/web`,
`services/media-worker`, and `services/playout-worker` from ChannelForge (all previously missing);
`packages/creative-worker` from ssaiadserver was already covered by the existing `packages`
wildcard copy. All four verified to build independently at the current pins — see
`docs/world-image-task-tracker.md` T3.1-T3.4 for build evidence. Note for Step 4's base image:
ssaiadserver's own `docker/Dockerfile` installs `ffmpeg`/`ffprobe` for the creative-worker; the
single-image `Dockerfile` needs the same system package. No build may read a moving branch.

The two old world glue patches are retired. Current upstream code provides
`CHANNELFORGE_ORIGIN_MAP` on the SSAI side and `CF_SSAI_BASE_URL` plus admin credentials on the
ChannelForge side. Do not restore the obsolete patches or their obsolete environment variables.

### Latest-upstream audit (2026-09-11 — `main` merged into `world`, pins now track `world`)

Superseded the 2026-09-09 snapshot below (T1.1/T1.2). Each repo's `main`-only commits that had
accumulated ahead of the old pin were merged into that repo's `world` branch, `world` was pushed
to origin, and the pins were re-pointed to the new `world` HEAD:

| Repository | Old pin (on `main`) | `main`-only commits merged in | New pin (`world` HEAD, post-merge) |
|---|---|---:|---|
| ChannelForge | `cdbf80b` | 9 (through `4f181f2`) | `bf56501` |
| ssaiadserver | `24c21d4` | 20 (through `eea3fec`), 2 conflicts hand-resolved | `8fccc2e` |
| fast-world-tv | `09193c2` | 11 (through `4400ffa`), 1 conflict hand-resolved | `52491a6` |

Conflict resolutions: ssaiadserver's `packages/core/src/index.ts` kept both branches' new exports
(`world-clock.js`/`world-event.js` from `world`, `opportunity-id.js` from `main`); its
`packages/control-plane/src/server.ts` kept `world`'s `emitWorldEvent` call alongside `main`'s
enriched `slots`/`opportunity_id` response fields — both changes are additive, not competing.
fast-world-tv's `src/app/layout.tsx` kept `world`'s env-driven `siteBaseUrl()` (the point of that
blueprint item) but took `main`'s accurate "four channels" copy — `world`'s "five channels" text
was stale from before a channel was retired (current `channels.ts` has 4 channels, 101–104).

`vendor/` was regenerated against the new pins via `scripts/vendor-source.sh` with no errors.

Going forward, re-run this audit as: `git fetch origin` in each source repo, then
`git log --oneline world..main` to see what upstream work hasn't been merged into `world` yet,
merge it in, push, and re-pin — same shape as before, just against `world` instead of `main`.

<details>
<summary>Superseded 2026-09-09 audit (pinned against <code>main</code>, before the <code>world</code>-branch policy)</summary>

The world pins remain unchanged while this document is drafted. A read-only fetch found these
new commits on upstream `main`:

| Repository | World pin | Fetched `origin/main` | Commits ahead | Relevant change |
|---|---|---|---:|---|
| ChannelForge | `cdbf80b` | `4f181f2` | 5 | real break barker, widened HLS window, current FAST-first UI/docs |
| ssaiadserver | `24c21d4` | `eea3fec` | 14 | live-edge avail detection/holdback, loop-to-fill, creative/admin work, contract tests |
| fast-world-tv | `09193c2` | `4400ffa` | 3 | working text/plain beacons and origin-timeline-aligned break markers |

These changes are directly relevant to a locally playable world. Before building the MVP image,
re-pin all three repositories in one reviewed change and re-run retained task Oracle/no-op checks.
Do not build an unrecorded mixture of pinned and latest source. Several Phase 3 task ideas describe
defects the new commits may already fix, so the task backlog must also be re-evaluated after the
re-pin.

</details>

**The five POC tasks (`task-05`..`task-09`) are archived, not migrated.** They were built,
hardened, and piloted against the pre-MVP four/nine-service Compose topology and the pins in
effect at the time. Re-pinning or moving to the single-image architecture invalidates the
assumptions either could depend on (e.g. `task-05`'s defect is documented as living in pristine
upstream source, not an injected patch — a future upstream fix silently removes it). Phase 1's
task backlog is a fresh set built against the re-pinned, single-image world; none of the POC tasks
carry forward, and none need re-validation under the new architecture.

## 3. Development topology and packaged topology

### Development

`world/docker-compose.yaml` is the source-of-truth integration topology used while developing:

- ChannelForge: API, scheduler, PostgreSQL, Redis;
- ssaiadserver: control plane, data plane, PostgreSQL, Redis; and
- fast-world-tv: viewer.

The latest upstream production shapes also include services omitted from the POC world:
ChannelForge's MinIO, media worker, playout worker, and HLS edge, plus ssaiadserver's creative
worker and object store. They are required for an MVP image that produces playable streams rather
than merely healthy APIs.

The ChannelForge operator frontend is not currently in that Compose file, but it is required in
the MVP image. Its pinned source is `apps/web`; its production build is static and is served by
nginx.

### Distribution

The distributable image co-locates the topology in one container. Supervisord is PID 1 and owns
the long-running processes. All service-to-service communication uses `127.0.0.1`; no Compose DNS
names remain in runtime configuration.

This monolithic runtime is an intentional distribution constraint. It does not replace Compose
as the preferred local-development architecture.

## 4. Runtime process and port map

Every program below starts automatically. “No port” means a continuously running worker, not an
optional or manually started component.

| Priority | Supervisor program | Internal port | Readiness dependency |
|---:|---|---:|---|
| 10 | ChannelForge PostgreSQL | 5432 | none |
| 10 | ChannelForge Redis | 6379 | none |
| 10 | SSAI PostgreSQL | 5433 | none |
| 10 | SSAI Redis | 6380 | none |
| 10 | MinIO object storage | 9000; console 9001 | none |
| 10 | local integration stub/collector | 9080 | none |
| 20 | ChannelForge API | 8000 | CF PostgreSQL, Redis, MinIO |
| 20 | SSAI control plane and admin UI | 4000 | SSAI PostgreSQL, Redis, MinIO |
| 25 | ChannelForge scheduler | no port | CF PostgreSQL and Redis |
| 25 | ChannelForge media worker | no port | CF PostgreSQL, Redis, MinIO |
| 25 | ChannelForge playout worker | no port | CF API, PostgreSQL, Redis, MinIO |
| 25 | SSAI creative worker | no port | SSAI PostgreSQL and MinIO |
| 30 | SSAI data plane | 4010 | SSAI control plane, Redis, MinIO, Forge origin |
| 30 | nginx: ChannelForge UI + raw HLS edge | 8080 | ChannelForge API and playout worker |
| 40 | fast-world-tv | 3000 | Forge edge and both SSAI planes |

Nginx serves the built `apps/web/dist` directory, proxies same-origin `/api` and `/health` requests
to `127.0.0.1:8000`, and serves the playout worker's HLS directory under `/hls`. Unlike the POC
world, the MVP must include the playout worker and edge so this route produces real local bytes.

Use non-default host ports so the world can run alongside ordinary development services:

| Host port | Published surface | Example |
|---:|---|---|
| 18080 | ChannelForge UI, API proxy, EPG, raw HLS | `http://localhost:18080/hls/<output>/delivery.m3u8` |
| 14000 | SSAI control plane and admin UI | `http://localhost:14000/admin` |
| 14010 | SSAI stitched HLS and media | `http://localhost:14010/v1/hls/<token>/<channel>/index.m3u8` |
| 13000 | FAST World viewer | `http://localhost:13000/fast-world/live` |
| 19001 | MinIO console, diagnostics only | `http://localhost:19001` |

These are default `docker run -p` mappings, not hardcoded application listen ports. An external
team may remap them. PostgreSQL, Redis, the ChannelForge API, MinIO's S3 port, and the local stub
remain unexposed by default.

## 5. Runtime configuration

Every Compose or production hostname is rewritten to loopback. At minimum this includes:

- both `DATABASE_URL` values;
- both `REDIS_URL` values;
- `CF_SSAI_BASE_URL`;
- `CHANNELFORGE_ORIGIN_URL` and, when available, `CHANNELFORGE_ORIGIN_MAP`;
- `CONTROL_PLANE_URL` and `DATA_PLANE_PUBLIC_URL`; and
- `FAST_HLS_101` through `FAST_HLS_105`.

The final configuration must contain no `forge.ventunotech.com`, `ssai.ventunotech.com`, Vercel,
Upstash, public test-stream, or other live-service fallback. Missing environment variables must
not silently reactivate an upstream hardcoded production URL.

Runtime secrets use sealed-world fixture values only. No model-provider key belongs inside the
image: Harbor supplies LLM credentials to the agent harness from the run server.

Distinguish internal service URLs from URLs returned to a browser. Internal calls use native
loopback ports such as `127.0.0.1:4000` and `127.0.0.1:4010`. Browser-visible playback URLs use the
configured world host and published defaults such as `localhost:14000` and `localhost:14010`.
Provide one runtime public-host setting so a remote team can replace `localhost` without rebuilding
the image. It must never default to a Ventuno production hostname.

The standalone smoke-test mode publishes the high host ports above. Evaluation mode must support
blocked external egress while preserving loopback communication among the co-located services.

### Write boundary in a shared filesystem

Discoverability is part of what a task evaluates: the agent is handed a problem, not a codebase,
and must determine which of the three application source trees actually needs the fix. The agent
therefore needs read (and, for the tree it identifies, write) access spanning all three source
trees inside the one container — this is a deliberate widening from the current per-service
Compose model, not an oversight.

What must stay off-limits regardless: a task's `tests/`, `solution/`, and `environment/`
directories, supervisor and nginx configuration, and both PostgreSQL data directories. In the
current multi-container model these are enforced by not being present in the agent's container at
all. A single shared filesystem removes that enforcement for free — it has to be built explicitly:
protected paths owned by root (or a dedicated service user) with no write bit for the user the
agent's shell runs as. **Do not assume the reference single-image precedent (`ventuno-world`,
§2 provenance note below) demonstrates this** — its application trees are uniformly owned by one
user (`www-data`) with no differentiated protection, because it is not itself a per-task graded
artifact. That ownership pattern is not safe to copy wholesale here; the permission scheme for
excluded paths needs its own design pass before Phase 1 build work starts.

### Observed external integrations

The upstream applications contain integrations that can make external calls. Most ChannelForge
integrations are opt-in and remain dormant when their credentials or destination configuration are
blank. FAST World requires extra care because some missing environment variables currently fall
back to Ventuno production URLs. The image must override those defaults explicitly; absence of a
setting is not an acceptable isolation mechanism.

| Application | External capability present upstream | MVP disposition |
|---|---|---|
| ChannelForge | YouTube and Google OAuth/APIs | credentials absent and integration disabled |
| ChannelForge | Google Drive and Dropbox import | credentials absent and integration disabled |
| ChannelForge | S3-compatible object storage | point exclusively to the in-container MinIO service |
| ChannelForge | SFTP import/export | disabled; add a local fixture server only when a task requires it |
| ChannelForge | RTMP, RTMPS, and SRT push destinations | use origin-only delivery; no public push destination |
| ChannelForge | SMTP, Slack, and generic webhooks | disabled or pointed exclusively at a local sink/collector |
| ChannelForge | production SSAI service | point exclusively to the in-container SSAI control plane |
| ssaiadserver | ChannelForge origin playlists and EPG | point exclusively to the local Forge HLS edge |
| ssaiadserver | S3-compatible creative storage | point exclusively to the in-container MinIO service |
| ssaiadserver | VAST tag and wrapper retrieval | use the deterministic local VAST stub; reject unknown hosts |
| ssaiadserver | third-party impression and tracking beacons | send only to the local beacon collector |
| fast-world-tv | ChannelForge HLS and EPG | use explicit local Forge URLs, including every seeded channel |
| fast-world-tv | SSAI session, stream, and event endpoints | use explicit local SSAI URLs |
| fast-world-tv | Upstash/Vercel KV | use its supported in-memory fallback; no Upstash credentials |
| fast-world-tv | poster, artwork, and other browser-fetched media | serve deterministic assets locally; no remote image URL |

This inventory describes capabilities in the upstream repositories, not services that the MVP is
expected to contact. The release configuration enables only local equivalents. Any newly found
integration is release-blocking until it is explicitly disabled, redirected to a deterministic
local service, or added to this table with a tested rationale.

### External-service replacements

| Upstream capability | MVP behavior |
|---|---|
| S3/object storage | one local MinIO process with separate ChannelForge and SSAI buckets |
| ChannelForge origin | real local playout worker + nginx HLS edge |
| SSAI origin dependency | `CHANNELFORGE_ORIGIN_MAP` points only to local Forge media playlists |
| FAST World HLS/EPG/SSAI defaults | explicit local URLs; never production fallback values |
| FAST World Upstash/Vercel KV | supported in-memory fallback, or a local adapter if persistence is required |
| VAST tags and tracking beacons | local deterministic VAST endpoint + beacon collector on port 9080 |
| generic webhooks/Slack | disabled unless pointed at the local HTTP collector |
| SMTP alerts | disabled by blank configuration; add a local SMTP sink only if an MVP task exercises email |
| YouTube, Google Drive, Dropbox | credentials absent and integrations disabled; no OAuth/API attempt |
| RTMP/SRT destinations | seeded channel runs origin-only; add a local sink only for a task that evaluates push output |

The local integration stub must expose a health endpoint and log deterministic requests for hidden
verification. It must not proxy unknown URLs. A fallback that reaches the public internet after a
local miss is prohibited.

## 6. Build layout

Create `world/image/Dockerfile` as a multi-stage Linux/amd64 build:

1. **Source stage** — consume the three locally vendored, pinned source trees. Network fetching
   source inside the Dockerfile is not the provenance mechanism.
2. **ChannelForge API stage** — install `apps/api` and shared packages using Python 3.12.
3. **ChannelForge web stage** — install and build `apps/web`; preserve the complete writable
   source tree as well as the generated `dist` assets.
4. **SSAI stage** — install and build all required Node packages once; the runtime environment
   selects control-plane or data-plane behavior.
5. **Worker/media stage** — install ChannelForge's media and playout workers plus FFmpeg; include
   deterministic programme, fallback/barker, ad, and slate source media.
6. **FAST web stage** — install with the pinned pnpm lockfile and run the production build using
   local world endpoints rather than its hardcoded production defaults.
7. **ChannelForge data stage** — initialize PostgreSQL, apply Alembic migrations, and load the
   approved ChannelForge sample fixture.
8. **SSAI data stage** — initialize the second PostgreSQL cluster, apply SSAI migrations, and run
   the persistence package's idempotent seed.
9. **Object-data stage** — initialize local MinIO buckets and load normalized programme media plus
   prepared ad/slate HLS objects whose keys match the two database fixtures.
10. **Final runtime stage** — install only the runtime/build tools needed for agent edits and
   explicit restarts, then copy application trees, built outputs, seeded database directories,
   seeded object data, supervisor configuration, nginx configuration, stub service, and lifecycle
   scripts.

The final base needs Python 3.12, Node 22, PostgreSQL 16, Redis 7, MinIO, nginx, supervisor, FFmpeg,
bash, patch, curl, and any media/build libraries required by the three pinned applications. Use a
Debian-family base unless implementation evidence demonstrates that mixing the required runtimes
and database packages on another base is simpler and equally reproducible.

Do not declare either PostgreSQL data directory as a Docker `VOLUME`. Image layers and
`docker commit` do not capture changes under a declared volume. The two database clusters must
also have distinct data directories, ports, Unix-socket directories, and log files.

### Child image per task

The distributed artifact from this Dockerfile is pristine, task-agnostic: pinned source, seeded
databases, no task-specific content baked in — the same separation of concerns as today's shared
`world/app/Dockerfile`/`world/db/Dockerfile` (AGENTS.md rule 4). Each task builds its own child
image `FROM` this base and applies its `setup/regression.patch` as a build-time step, the same
shape as today's per-task `environment/Dockerfile`, just against a much richer base.

This raises one question the ten stages above must each answer explicitly: which of them are
reusable, final base layers, and which have to re-run inside a task's child build when its patch
touches source those stages already consumed? A patch to `apps/api` is cheap to apply after the
fact; a patch to something `apps/web`'s stage 3 already compiled to `dist`, or a schema change a
task needs that stage 7's migrations already ran, is not — the child build needs to re-trigger the
affected downstream stage(s), not just layer a source patch on top of their already-baked output.
Mark each of the ten stages above as "safe to patch after" or "must be re-run by the child build"
before implementation starts.

## 7. Required preloaded data

Both PostgreSQL databases are preloaded during the image build. Seeding at first container start
is not the MVP contract: a fresh container must already contain the baseline data.

### ChannelForge database

Use `scripts/seed_fixture.py` as the starting implementation for the synthetic **Yoga & You**
tenant. It currently produces:

- 1 organization and owner;
- 30 assets across 6 collections;
- 4 programming blocks;
- 1 channel;
- 1 published schedule with 113 events; and
- as-run entries for the elapsed portion of the schedule.

The seed combines API-level creation for validated application objects with direct ORM inserts
only where the sealed world lacks a real ingest pipeline. Before MVP release, remove the remaining
claim that some titles are production-derived or replace those titles with fully synthetic
equivalents. The release fixture must contain no customer-derived data or PII.

The current fixture's storage rows point at objects that do not exist. The MVP seed must instead
reference deterministic, synthetic media placed in local MinIO. At least one seeded channel must
be configured for origin-only delivery, have a published rolling schedule and valid distribution
state, and be desired-running at boot so the supervised playout worker emits HLS without a manual
API call. Its fallback media and ad-break barker must also resolve locally.

### SSAI database

Use `vendor/ssaiadserver/packages/persistence/src/seed.ts` through its supported seed command.
It idempotently creates five demo channels plus campaigns and 15/30/60-second creatives.

The SSAI campaign dates are currently fixed to calendar year 2026 and its origin URLs use an old
hostname/path shape. Phase 1 must make the sample inventory calendar-stable and rewrite origins to
valid in-world URLs. The seeded ChannelForge and SSAI channel identities must either be aligned for
an end-to-end demo or their intentionally separate roles must be stated in the release README.

Rows alone are insufficient: generate fully synthetic ad and slate source clips during the build,
run them through the real creative-worker preparation path, and preload their HLS objects into the
SSAI MinIO bucket. At least one seeded SSAI channel must map to the running local Forge media
playlist and return a manifest containing locally served ad or slate segments.

### Time and reset determinism

The existing ChannelForge fixture calls the wall clock and creates a rolling 24-hour schedule.
Baking it unchanged would make a distributed image stale shortly after it was built. Before the
fixture counts as MVP-ready, choose and implement one deterministic rule:

- build against a documented fixed world epoch and run the world against that virtual time; or
- rebase only time-dependent fixture rows through one deterministic world-reset operation.

Whichever rule is chosen, two fresh containers from the same image must expose equivalent sample
state, and the sample must still be usable after the image has been stored and downloaded later.
No task may depend on unseeded randomness or the host's current date.

## 8. Process ownership and restart contract

Supervisord must detect and restart unexpected service exits. It therefore needs to supervise the
actual long-running process, not an immortal wrapper whose child can die unnoticed.

The evaluated agent still receives exactly one named restart verb per editable service:

- `restart-api`;
- `restart-cf-web`;
- `restart-media-worker`;
- `restart-playout-worker`;
- `restart-ssai-control`;
- `restart-ssai-data`;
- `restart-ssai-creative-worker`; and
- `restart-fast-web`.

Each command rebuilds when its language/runtime requires it and asks supervisor to restart only
the corresponding program. There is no alternate restart path and no file watcher. A failure from
the named command is surfaced as a failure; scripts must not fall back to starting an unmanaged
duplicate process.

The scheduler is not independently agent-editable in current tasks. If a future task needs it,
that task must explicitly add one canonical scheduler restart verb rather than overloading
`restart-api`. Data stores, nginx, MinIO, and the stub service are world infrastructure and are not
agent restart targets unless a future task explicitly makes one writable.

Supervisord has no native `depends_on` — a program's `priority` number only orders *start attempts*,
not readiness. The reference single-image precedent (`ventuno-world`, §9) handles this with an
explicit wrapper (`wait-for-mysql.sh`) blocking Apache's start until MySQL answers, rather than
relying on priority ordering alone; it also exposes bare `supervisorctl` rather than per-service
restart scripts. This repo's guardrail (AGENTS.md rule 2: exactly one named restart verb per
service, never a generic fallback) is stricter and should be kept — but each restart verb still
needs its own explicit readiness guard for whatever it depends on, the same way `wait-for-mysql.sh`
does, rather than assuming supervisord's priority table enforces it.

## 9. Harbor compatibility

**Reference precedent, verified 2026-09-10:** `ventuno-world:0.2.0`
(`sha256:508b2d66087d1046c36dae895ce186efed35cc072ed878b0b8a3fc643d438b0c`), a real single-image
world built for Horizon (a platform on top of Harbor), was inspected directly. Its `ENTRYPOINT` is
the stock, transparent `docker-php-entrypoint` (`exec "$@"`); its `CMD` is
`/usr/bin/supervisord -c /etc/supervisor/supervisord.conf`. Run with a bare `docker run` and no
command override, supervisord started as PID 1 and all 14 supervised programs (MySQL, Memcached,
Solr, Apache/PHP, RabbitMQ, four cron jobs, a Node SSR service, a builder, nginx, mailpit) reached
`RUNNING` within 15 seconds, confirmed via `supervisorctl status`.

This image has **no defense against a `command:` override** — nothing in it (no `ENTRYPOINT`
trick, no wrapper) would survive being wrapped in a compose service that had its `command`
rewritten the way Harbor's local Docker provider rewrites a `main` service's command to
`sh -c "sleep infinity"`. It works here because it is evidently run as a standalone container,
not through Harbor's compose-based `main`-service build/overlay path.

**Resolved 2026-09-11 (T2.1-T2.4).** Confirmed with the Horizon harness owner: `ventuno-world`
does run through Harbor's `docker` environment provider — the `sleep infinity` override problem
above is real, not hypothetical, for this world too.

Built and smoke-tested a throwaway supervisord-only image (Ubuntu 24.04 + `supervisor` + two
dummy heartbeat programs, no application stages) against Harbor's real `docker` environment
provider via `harbor task start-env -p <task-dir> -i`, which builds the environment through
Harbor's actual compose-overlay path (the same one a real task run uses):

- **Naive baseline (bare `CMD supervisord ...`, matching `ventuno-world`'s pattern) fails exactly
  as predicted.** `ps aux` inside the running `main` container showed PID 1 as `sh -c "sleep
  infinity"` — supervisord never started at all: no `/var/run/supervisor.sock`, no supervised
  programs, nothing. Harbor's compose overlay fully replaces the image's `CMD`.
- **Fix: an `ENTRYPOINT` script that ignores its arguments and unconditionally execs
  supervisord**, e.g.:
  ```dockerfile
  COPY start-supervisord.sh /usr/local/bin/start-supervisord.sh
  ENTRYPOINT ["/usr/local/bin/start-supervisord.sh"]
  ```
  ```bash
  #!/bin/bash
  # Deliberately ignores "$@" — Harbor appends sleep-infinity args here.
  exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
  ```
  Because Harbor's compose overlay only overrides the service's `command:` (→ Docker `CMD`), not
  `ENTRYPOINT`, and this entrypoint never references `"$@"`, the appended `sleep infinity` args
  are silently discarded and supervisord always becomes the container's real PID 1 — verified:
  `ps aux` showed `supervisord` as PID 1, `supervisorctl status` reported both dummy programs
  `RUNNING`, and their heartbeat log files were actively being written. Harbor's own interactive
  shell attachment (`docker exec`-based, not dependent on what PID 1 is) still worked normally
  against this container throughout the test — confirming the fix doesn't trade away shell access.

**Adopt this `ENTRYPOINT`-ignores-args pattern for the real single-image `Dockerfile`** (§6) —
do not reuse `ventuno-world`'s bare-`CMD` pattern as-is, it does not survive Harbor's actual
overlay behavior.

Application source is writable inside the trial. The base image must not contain task-specific
regressions. A task-specific child image applies only its declared regression to only its declared
writable source trees.

## 10. Tagging and future publication

Use semantic image tags such as `channelforge-world:0.1.0` plus an immutable digest. Increment the
version for source re-pins, fixture changes, runtime changes, or changes that alter task behavior.

The publication implementation is deferred, but it must eventually provide:

- an immutable Google Artifact Registry reference;
- access instructions for external teams;
- the release manifest with all source commits and image digest;
- supported host architecture and minimum resource requirements; and
- rollback instructions that select an earlier immutable tag or digest rather than overwriting a
  published release.

## 11. Acceptance gate

A candidate image is not publishable until all of the following pass:

1. A clean Linux/amd64 build succeeds from the pinned inputs.
2. `docker run` boots with supervisord as PID 1 and every required program remains `RUNNING`.
3. ChannelForge UI, ChannelForge API, SSAI control, SSAI data, and FAST viewer health checks pass.
4. Scheduler, media worker, playout worker, creative worker, MinIO, nginx, and the local stub all
   remain running after startup.
5. Both PostgreSQL databases contain their expected migrations and exact sample-data inventory.
6. Local MinIO contains every programme, fallback, ad, and slate object referenced by seeded rows.
7. Two fresh containers expose equivalent seeded state without executing an external seed step.
8. Seeded rights, campaign dates, schedules, and origins remain usable at the documented world
   time.
9. The raw Forge media playlist and its segments are continuously playable through host port
   `18080`.
10. A session created through host port `14000` yields an SSAI manifest on `14010` whose content,
    ad, and slate segment URLs all resolve locally.
11. FAST World on `13000` plays the local stitched session and reads the local EPG without any
    production URL in its browser or server request log.
12. Each agent-facing restart verb rebuilds/restarts the intended service and no other service.
13. Unexpectedly killing a supervised service causes supervisor to recover it without creating a
   duplicate.
14. Runtime external egress is blocked in the evaluation configuration, while positive checks
    prove all required loopback calls still work. **This depends on closing this repo's currently
    open `network_mode="no-network"` gap** (not yet enforced under the local Docker provider — no
    egress-control sidecar wired up, per `docs/harbor-install.md`/AGENTS.md); that closure is
    scoped as its own tracked step in §12, not assumed here.
15. A DNS/HTTP capture of the smoke test contains no request to a public hostname; VAST, beacon,
    webhook, storage, origin, EPG, telemetry, and playback requests terminate inside the world.
16. `docker history` and a layer inspection confirm no `tasks/*/tests`, `tasks/*/solution`, `.env`,
    job transcript, API key, or private fixture input exists in any final layer.
17. Every Phase 1 task, built fresh against the re-pinned single-image world, passes a real Harbor
    Oracle run and fails a real no-op run against the packaged image. (The five POC tasks are
    archived, not retained — see §2's provenance note.)
18. A fresh run server can pull or load the artifact and complete the smoke test without access to
    the three source repositories.

## 12. First implementation sequence

1. Re-run the upstream audit (§2.1) to confirm it hasn't gone stale, then decide and execute the
   coordinated three-repo re-pin. No POC task revalidation is needed — they're archived (§2).
2. Build and smoke-test a throwaway supervisord-only image against Harbor's real `docker`
   environment provider, resolving §9's open command-override question, before any application
   stages are added. Do not proceed to step 3 until this passes for real, not simulated.
3. Extend vendoring to include `apps/web`, both ChannelForge workers, and all SSAI worker/runtime
   packages; verify application builds independently.
4. Create the final base, supervisor configuration, nginx/HLS edge, MinIO, and local stub without
   sample data. Design and implement the write-boundary permission scheme (§5) at this stage —
   before any task-specific child images depend on it.
5. Prove every process autostarts and replace all production/public endpoints with local ones.
6. Create synthetic programme media, adapt the ChannelForge fixture, and prove raw HLS playback.
7. Create synthetic ad/slate media, bake the SSAI fixture, and prove stitched HLS playback.
8. Wire FAST World to local EPG/origin/SSAI endpoints and prove browser playback.
9. Close the `network_mode="no-network"` gap (egress-control sidecar, or an environment provider
   that natively supports it) as its own scoped work item — a prerequisite for acceptance gate
   items 14–15, not a byproduct of the stages above.
10. Prototype the child-image-per-task build (§6) against one representative Phase 1 task idea,
    confirming which base stages survive a source patch unchanged and which must re-run.
11. Run the full acceptance gate, including outbound-call capture.
12. Decide and document Google Artifact Registry publication.
