# Task-specific: pristine ChannelForge source + this task's regression, baked at build time.
# There is no Harbor-recognized "runtime setup hook" — a task's environment is fully defined by
# what its own Dockerfile builds. Build context is the channelforge-world repo root (set by this
# task's environment/docker-compose.yaml).

FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg curl patch \
    && rm -rf /var/lib/apt/lists/*

COPY vendor/apps/api /app
COPY vendor/packages /packages
RUN pip install --no-cache-dir -e /packages/media-engine \
    && pip install --no-cache-dir -e ".[dev]"

COPY scripts/restart-api.sh /usr/local/bin/restart-api
RUN chmod +x /usr/local/bin/restart-api

# The regression, baked in at build time. Kept at a fixed path so solution/solve.sh (the Oracle,
# run outside this build) can reverse it at runtime.
COPY tasks/task-01-rights-window-bugfix/setup/regression.patch /opt/task-setup/regression.patch
RUN patch -p1 < /opt/task-setup/regression.patch

EXPOSE 8000
CMD ["/usr/local/bin/restart-api", "--foreground"]
