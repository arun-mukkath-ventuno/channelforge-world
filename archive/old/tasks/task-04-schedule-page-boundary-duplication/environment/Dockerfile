# Task-specific: pristine fast-world-tv source + this task's regression, baked at build time.
# Build context is the channelforge-world repo root (set by this task's environment/
# docker-compose.yaml). fast-world-tv ships with no test tooling at all (no vitest devDependency,
# no test script) — this task adds vitest as an image-level devDependency (not touching
# vendor/fastworldtv's own lockfile) so the guide's time-window logic can be verified at the
# code level. Live serving still works via restart-fast-web, same as world/fastweb/Dockerfile,
# in case the agent wants to exercise it manually — the grader itself doesn't need it.

FROM node:22-alpine

RUN apk add --no-cache bash patch && corepack enable && corepack prepare pnpm@9.12.0 --activate

WORKDIR /app

COPY vendor/fastworldtv/package.json vendor/fastworldtv/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
RUN pnpm add -D vitest@^2

COPY vendor/fastworldtv/src ./src
COPY vendor/fastworldtv/public ./public
COPY vendor/fastworldtv/tsconfig.json vendor/fastworldtv/next.config.ts \
     vendor/fastworldtv/postcss.config.mjs vendor/fastworldtv/eslint.config.mjs ./

# Vitest (via its underlying Vite instance) auto-loads postcss.config.mjs from the project root
# during config resolution regardless of test.css — and that config's Tailwind v4 plugin isn't a
# shape Vite's PostCSS loader accepts standalone, unrelated to the pure logic under test here.
# Passing an inline (empty) postcss config bypasses the file-search entirely.
RUN printf 'import { defineConfig } from "vitest/config";\nexport default defineConfig({ css: { postcss: { plugins: [] } } });\n' > vitest.config.ts

# The regression, baked in at build time. Kept at a fixed path so solution/solve.sh (the Oracle,
# run outside this build) can reverse it at runtime.
COPY tasks/task-04-schedule-page-boundary-duplication/setup/regression.patch /opt/task-setup/regression.patch
RUN patch -p1 < /opt/task-setup/regression.patch

COPY scripts/restart-fast-web.sh /usr/local/bin/restart-fast-web
RUN chmod +x /usr/local/bin/restart-fast-web

EXPOSE 3000
CMD ["/usr/local/bin/restart-fast-web", "--foreground"]
