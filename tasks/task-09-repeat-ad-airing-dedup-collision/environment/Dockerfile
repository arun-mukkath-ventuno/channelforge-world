# Task-specific: pristine fastworldtv source, no regression patch — the defect (sendAdBeacon
# dropping the one piece of information, the ad window's own start time, that would let the
# server's existing pod_id-aware dedup key tell two separate airings of the same creative apart)
# is already present in the pinned pristine source itself, not something injected for this task.
# Build context is the channelforge-world repo root (set by this task's environment/docker-
# compose.yaml). Mirrors world/fastweb/Dockerfile.
#
# Cross-repo reference material (confirmed necessary — see docs/ecosystem.md's task-09 note): the
# events endpoint this fix's payload is consumed by is ssaiadserver's, a separate repo the agent
# would otherwise have zero visibility into. Without this, a correct-shaped fix that invents its
# own field name (rather than the one the real dedup key reads) is indistinguishable from a correct
# one *from inside this container alone* — not a legitimately diagnosable task, just a guess. A
# read-only copy of the actual consuming code (never built, never on the fix's own path) gives the
# agent the same access a real engineer fixing this bug would have: grep the other repo.

FROM node:22-alpine

RUN apk add --no-cache bash && corepack enable && corepack prepare pnpm@9.12.0 --activate

WORKDIR /app

COPY vendor/fastworldtv/package.json vendor/fastworldtv/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY vendor/fastworldtv/src ./src
COPY vendor/fastworldtv/public ./public
COPY vendor/fastworldtv/tsconfig.json vendor/fastworldtv/next.config.ts \
     vendor/fastworldtv/postcss.config.mjs vendor/fastworldtv/eslint.config.mjs ./
RUN pnpm build

COPY scripts/restart-fast-web.sh /usr/local/bin/restart-fast-web
RUN chmod +x /usr/local/bin/restart-fast-web

# Read-only reference: the SSAI event-ingestion service this player posts beacons to (a separate
# repo/service, not built or run here — /v1/events is not reachable from this container). Not
# under /app so it's clearly not part of this repo's own source tree.
COPY vendor/ssaiadserver/packages/control-plane/src/events-normalize.ts \
     /reference/ssaiadserver/control-plane/events-normalize.ts
COPY vendor/ssaiadserver/packages/persistence/src/repositories/events.ts \
     /reference/ssaiadserver/persistence/repositories/events.ts

EXPOSE 3000
CMD ["/usr/local/bin/restart-fast-web", "--foreground"]
