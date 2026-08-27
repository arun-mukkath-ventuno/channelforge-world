# The Yoga & You fixture, and the scheduler-sweep decision

Two POC Scope open items, closed together: whether to run ChannelForge's background scheduler
live or fake its output, and building the "Yoga & You" synthetic tenant. See
[`how-it-works.md`](how-it-works.md) for how these fit into the wider world; this doc covers what
each actually is and how to reproduce them.

## Scheduler sweep: decided — run it live

`app/jobs/scheduler.py` is ChannelForge's own standalone background loop (normally its own
docker-compose service in production), ticking every 15s through ~9 reconciliation sweeps:
heartbeat-staleness, start-timeout, quickstart, horizon auto-extend, schedule-horizon, upcoming-
media, YouTube-connection health, YouTube-broadcast reconciliation, audience-metrics sampling.

**Decision: run it live**, as a 4th compose service (`scheduler` in `world/docker-compose.yaml`)
— same image as `main`, just `command: ["python", "-m", "app.jobs.scheduler"]` instead of
`restart-api`. No new Dockerfile needed.

**Why this is safe without a real playout-worker**, confirmed by reading the sweep functions, not
assumed: every sweep that could touch the network (the two YouTube sweeps, audience-metrics)
either only checks channels with `desired_state == "running"`, or additionally requires
`channel.state == "running"`. Nothing in this world ever reaches `state == "running"` — there's no
live playout-worker to send a heartbeat — so those sweeps are automatically safe no-ops. This
didn't need a code change or a guard; it falls out of the sealed world's own shape.

**Verified in practice**: ran for 3+ sweep cycles (45s+) against the real seeded fixture with zero
exceptions and zero unwanted side effects — the fixture's one channel is `desired_state: stopped`,
so even the heartbeat sweep skips it entirely (`list_desired_running` only returns
`desired_state == "running"` channels).

## The Yoga & You fixture

`scripts/seed_fixture.py` builds a synthetic org matching POC Scope's spec: one organization,
30 assets across 6 collections (Morning Yoga, Beginner Sessions, Advanced Sessions, Meditation,
Bumpers, Filler), 4 programming blocks, one channel, one published schedule (113 events), and
58 as-run entries covering the already-past portion of that schedule.

**How it builds valid data**: mirrors the pattern `tests/helpers.py` already uses — real API calls
(signup, collections, programming blocks, channel, schedule generate+publish) for anything with
real validation logic worth exercising, and direct ORM inserts only for `Asset`/`MediaVersion`
(the one thing this sealed world has no real pipeline for — no ffprobe, no S3 — so
`compatibility_state` is set directly to `"compatible"`, same as the test suite already does).
Because `schedule/publish` goes through the real API, ChannelForge's own validation (including
rights-window checks) already confirmed the data is legitimately valid — not just "didn't error."

**Content provenance, stated plainly**: 10 of the 30 asset titles (Beginner/Advanced Sessions) are
real, taken from an internal pilot org's actual asset library (a prod dump shared by the team,
`"Ventuno Yoga"`, org id `cb4a0bac-80b0-4b3a-a739-7b8d61b33329`) — titles and real durations, no
other data from that org. Everything else (Morning Yoga, Meditation, Bumpers, Filler content, and
the whole collection/channel/schedule structure) is purpose-built for this fixture. The real org
wasn't imported wholesale — it was too operationally messy for a sealed fixture (live `running`
state, 24,188 real schedule events, unrelated craft-video content mixed into the same library).

### Reproducing it

```bash
./scripts/bake-fixture-db.sh
```

This boots a throwaway world stack, runs migrations, runs `seed_fixture.py` against the live API,
stops Postgres cleanly, and `docker commit`s it into `channelforge-world-db:yoga-and-you`. Use it:

```bash
docker compose -f world/docker-compose.yaml -f world/docker-compose.fixture.yaml up -d
```

### The `docker commit` / `VOLUME` gotcha that broke this the first time

The first bake attempt produced an image that looked right (correct size, `docker commit`
succeeded) but booted **empty** — no tables at all. Root cause: the official `postgres:16` image
declares `VOLUME /var/lib/postgresql/data` in its own Dockerfile, and **`docker commit` never
captures data stored inside a declared volume** — this is standard, documented Docker behavior,
not a bug in our approach. Fix: `world/db/Dockerfile` now sets `ENV PGDATA=/var/lib/postgresql/cf-data`,
moving Postgres's data directory off the volume-declared path entirely, onto a plain image layer
`docker commit` actually captures. Confirmed by booting a fresh container from the baked image
with no compose stack at all and querying it directly — data was present with zero seeding.

This is the same category of lesson as `restart-api`'s PID-1 bug and the Horizon-migration infra
failure: verified by actually running it, not assumed from documentation.
