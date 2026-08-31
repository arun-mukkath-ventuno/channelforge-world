# channelforge-world fast-web image — the fast-world-tv Next.js viewer.
#
# Build context is the channelforge-world repo root (run scripts/vendor-source.sh first so
# vendor/fastworldtv/ exists). Built once (`next build`) and served with `next start` — no
# `next dev`/file-watcher anywhere in this world: a code edit only takes effect once
# restart-fast-web is run, deliberately, by the agent.

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

EXPOSE 3000
CMD ["/usr/local/bin/restart-fast-web", "--foreground"]
