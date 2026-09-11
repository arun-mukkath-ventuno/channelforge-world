# channelforge-world single image (docs/devops-single-image.md §6, §12 step 3-4).
#
# Build context is the channelforge-world repo root (run scripts/vendor-source.sh first so
# vendor/ exists). This is a first working cut, not yet the full 10-stage cacheable structure
# from the spec: everything installs into one Ubuntu 24.04 base rather than being split across
# per-app build stages copied forward with COPY --from. Splitting for build-cache/size is a
# documented follow-up (see docs/devops-single-image.md §6 note), not required for T4.1-T4.5.
#
# No sample data is baked here (Steps 6/7/13/15 do that separately) — this Dockerfile only gets
# the runtime processes themselves installed, configured, and able to reach RUNNING.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1

# ── System packages ─────────────────────────────────────────────────────────────────────────
# Python 3.12, Node 22, PostgreSQL 16, Redis 7, nginx, supervisor, FFmpeg, bash, patch, curl —
# everything the spec's §6 build-layout section requires on one Debian-family base.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg patch bash build-essential \
        python3.12 python3.12-venv python3-pip \
        postgresql-16 postgresql-client-16 \
        redis-server \
        nginx supervisor \
        ffmpeg \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && rm -rf /var/lib/apt/lists/*

# MinIO — not packaged for apt; install the official static binary directly.
RUN curl -fsSL https://dl.min.io/server/minio/release/linux-amd64/minio -o /usr/local/bin/minio \
    && chmod +x /usr/local/bin/minio

# ── ChannelForge API (stage 2) ──────────────────────────────────────────────────────────────
WORKDIR /app
COPY vendor/apps/api /app
COPY vendor/packages /packages
RUN pip install --break-system-packages --no-cache-dir -e /packages/media-engine \
    && pip install --break-system-packages --no-cache-dir -e ".[dev]"

# ── ChannelForge web (stage 3) ───────────────────────────────────────────────────────────────
WORKDIR /web
COPY vendor/apps/web /web
RUN npm install && npm run build

# ── ChannelForge media + playout workers (stage 5, minus the media itself — that's Step 6) ──
WORKDIR /media-worker
COPY vendor/services/media-worker /media-worker
RUN pip install --break-system-packages --no-cache-dir -e /packages/media-engine \
    && pip install --break-system-packages --no-cache-dir -e ".[dev]"

WORKDIR /playout-worker
COPY vendor/services/playout-worker /playout-worker
RUN pip install --break-system-packages --no-cache-dir -e /packages/media-engine \
    && pip install --break-system-packages --no-cache-dir -e /app \
    && pip install --break-system-packages --no-cache-dir -e ".[dev]"

# ── ssaiadserver: control plane, data plane, creative worker (stage 4) ──────────────────────
WORKDIR /ssai
COPY vendor/ssaiadserver/package.json vendor/ssaiadserver/package-lock.json* \
     vendor/ssaiadserver/tsconfig.base.json vendor/ssaiadserver/tsconfig.json ./
COPY vendor/ssaiadserver/packages ./packages
COPY vendor/ssaiadserver/migrations ./migrations
RUN npm install && npm run build

# ── fast-world-tv (stage 6) ──────────────────────────────────────────────────────────────────
WORKDIR /fastweb
RUN corepack prepare pnpm@9.12.0 --activate
COPY vendor/fastworldtv/package.json vendor/fastworldtv/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY vendor/fastworldtv/src ./src
COPY vendor/fastworldtv/public ./public
COPY vendor/fastworldtv/tsconfig.json vendor/fastworldtv/next.config.ts \
     vendor/fastworldtv/postcss.config.mjs vendor/fastworldtv/eslint.config.mjs ./
RUN pnpm build

# ── PostgreSQL: two independent clusters (spec §6: distinct data dirs, ports, sockets, logs) ─
# cf-data reuses the moved-off-VOLUME-path lesson from world/db/Dockerfile; ssai-data is new,
# on its own port (5433) and its own Unix-socket directory so the two clusters never collide.
RUN mkdir -p /var/lib/postgresql/cf-data /var/lib/postgresql/ssai-data \
             /var/run/postgresql/cf /var/run/postgresql/ssai \
    && chown -R postgres:postgres /var/lib/postgresql/cf-data /var/lib/postgresql/ssai-data \
                                    /var/run/postgresql/cf /var/run/postgresql/ssai \
    && su postgres -c "/usr/lib/postgresql/16/bin/initdb -D /var/lib/postgresql/cf-data" \
    && su postgres -c "/usr/lib/postgresql/16/bin/initdb -D /var/lib/postgresql/ssai-data"

# ── Redis: two independent instances (6379 for CF, 6380 for SSAI) ──────────────────────────
RUN mkdir -p /var/lib/redis/cf /var/lib/redis/ssai /var/run/redis \
    && chown -R redis:redis /var/lib/redis/cf /var/lib/redis/ssai /var/run/redis

# ── MinIO data root + local stub ─────────────────────────────────────────────────────────────
RUN mkdir -p /var/lib/minio/data /var/log/local-stub
COPY world/image/stub/stub_server.py /opt/local-stub/stub_server.py

# ── Supervisor, nginx, entrypoint, readiness guards, restart verbs ──────────────────────────
COPY world/image/supervisord.conf /etc/supervisor/supervisord.conf
COPY world/image/nginx.conf /etc/nginx/nginx.conf
COPY world/image/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY world/image/wait-for-tcp.sh /opt/wait-for-tcp.sh
COPY world/image/restart/ /opt/restart/
RUN chmod +x /usr/local/bin/entrypoint.sh /opt/wait-for-tcp.sh /opt/restart/*.sh \
    && ln -sf /opt/restart/restart-api.sh /usr/local/bin/restart-api \
    && ln -sf /opt/restart/restart-cf-web.sh /usr/local/bin/restart-cf-web \
    && ln -sf /opt/restart/restart-media-worker.sh /usr/local/bin/restart-media-worker \
    && ln -sf /opt/restart/restart-playout-worker.sh /usr/local/bin/restart-playout-worker \
    && ln -sf /opt/restart/restart-ssai-control.sh /usr/local/bin/restart-ssai-control \
    && ln -sf /opt/restart/restart-ssai-data.sh /usr/local/bin/restart-ssai-data \
    && ln -sf /opt/restart/restart-ssai-creative-worker.sh /usr/local/bin/restart-ssai-creative-worker \
    && ln -sf /opt/restart/restart-fast-web.sh /usr/local/bin/restart-fast-web

RUN mkdir -p /var/log/supervisor /var/lib/channelforge/hls

# ── T4.1: write-boundary permission scheme (advisory/structural only — see
# docs/devops-single-image.md §5 for why this is not yet real enforcement: Harbor's docker
# environment provider has no task.toml-level way to exec agent commands as a non-root user, and
# no capability-dropping either, so a root agent shell can bypass this regardless. Building it
# anyway means it becomes real enforcement for free the moment Harbor closes that gap, and it
# documents intent in the meantime.
#
# Both PostgreSQL data directories are deliberately NOT re-chowned here: they already belong to
# the `postgres` user from the initdb step above (mode 0700, postgres's own default), which
# already keeps `worldagent` out — re-chowning to root would break postgres's own refusal to run
# against a data directory it doesn't own. ──────────────────────────────────────────────────────
RUN useradd -u 2000 -m -s /bin/bash worldagent \
    && chown -R worldagent:worldagent /app /web /media-worker /playout-worker /packages /ssai /fastweb \
    && chmod -R 755 /app /web /media-worker /playout-worker /packages /ssai /fastweb \
    && chown -R root:root /etc/supervisor /etc/nginx /opt/local-stub \
    && chmod -R 750 /etc/supervisor /etc/nginx /opt/local-stub

EXPOSE 8000 8080 4000 4010 3000 9000 9001 9080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
