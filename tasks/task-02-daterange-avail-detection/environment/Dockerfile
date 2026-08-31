# Task-specific: pristine ssaiadserver source, no regression patch — the defect (detectAvails
# never recognizing DATERANGE cues) is already present in the pinned pristine source itself, not
# something injected for this task. Build context is the channelforge-world repo root (set by
# this task's environment/docker-compose.yaml).

FROM node:22-alpine

RUN apk add --no-cache bash patch

WORKDIR /app

COPY vendor/ssaiadserver/package.json vendor/ssaiadserver/package-lock.json* \
     vendor/ssaiadserver/tsconfig.base.json vendor/ssaiadserver/tsconfig.json ./
COPY vendor/ssaiadserver/packages ./packages
RUN npm install
RUN npm run build

COPY scripts/restart-ssai.sh /usr/local/bin/restart-ssai
RUN chmod +x /usr/local/bin/restart-ssai

ENV SSAI_SERVICE=data-plane
CMD ["/usr/local/bin/restart-ssai", "--foreground"]
