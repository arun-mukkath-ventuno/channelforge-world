# channelforge-world ssaiadserver image — shared by the ssai-control and ssai-data compose
# services (same image, picked at container start via the SSAI_SERVICE env var, mirroring
# ssaiadserver's own docker/Dockerfile ARG SERVICE split).
#
# Build context is the channelforge-world repo root (run scripts/vendor-source.sh first so
# vendor/ssaiadserver/ exists). No --watch/nodemon: restarts are explicit, via
# /usr/local/bin/restart-ssai (see scripts/restart-ssai.sh).

FROM node:22-alpine

RUN apk add --no-cache bash

WORKDIR /app

COPY vendor/ssaiadserver/package.json vendor/ssaiadserver/package-lock.json* \
     vendor/ssaiadserver/tsconfig.base.json vendor/ssaiadserver/tsconfig.json ./
COPY vendor/ssaiadserver/packages ./packages

RUN npm install
RUN npm run build

COPY scripts/restart-ssai.sh /usr/local/bin/restart-ssai
RUN chmod +x /usr/local/bin/restart-ssai

# SSAI_SERVICE (control-plane | data-plane) is set per compose service, not baked into the image.
CMD ["/usr/local/bin/restart-ssai", "--foreground"]
