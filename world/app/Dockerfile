# channelforge-world app image — ChannelForge API with a writable source tree.
#
# Build context is the channelforge-world repo root (run `scripts/vendor-source.sh` first so
# vendor/ exists). No --reload: restarts are explicit, via /usr/local/bin/restart-api.

FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg curl \
    && rm -rf /var/lib/apt/lists/*

COPY vendor/apps/api /app
COPY vendor/packages /packages

RUN pip install --no-cache-dir -e /packages/media-engine \
    && pip install --no-cache-dir -e ".[dev]"

COPY scripts/restart-api.sh /usr/local/bin/restart-api
RUN chmod +x /usr/local/bin/restart-api

EXPOSE 8000
CMD ["/usr/local/bin/restart-api", "--foreground"]
