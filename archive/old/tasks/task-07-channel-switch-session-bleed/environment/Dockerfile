# Task-specific: pristine ssaiadserver source, no regression patch — the defect (a session's
# recorded channel_id never updates once set, because ensureSession's INSERT uses ON CONFLICT (id)
# DO NOTHING) is already present in the pinned pristine source itself, not something injected for
# this task. Build context is the channelforge-world repo root (set by this task's environment/
# docker-compose.yaml).

FROM node:22-alpine

RUN apk add --no-cache bash patch

WORKDIR /app

COPY vendor/ssaiadserver/package.json vendor/ssaiadserver/package-lock.json* \
     vendor/ssaiadserver/tsconfig.base.json vendor/ssaiadserver/tsconfig.json ./
COPY vendor/ssaiadserver/packages ./packages
# The verifier's persistence/control-plane test files load the real migrations as their pg-mem
# schema (same pattern the pristine repositories.test.ts/server.test.ts already use) — those live
# at the ssaiadserver repo root, not under packages/, so they need their own COPY into the image.
COPY vendor/ssaiadserver/migrations ./migrations
RUN npm install
RUN npm run build

COPY scripts/restart-ssai.sh /usr/local/bin/restart-ssai
RUN chmod +x /usr/local/bin/restart-ssai

ENV SSAI_SERVICE=control-plane
CMD ["/usr/local/bin/restart-ssai", "--foreground"]
