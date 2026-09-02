# Task-specific: the first genuinely two-repo-writable task in this world (docs/workflow.md's
# colocated-`main` model). Both ChannelForge's API source (/app) and ssaiadserver's source
# (/ssai) live in this one container, each with this task's regression patch applied on top of
# pristine pinned source (+ world/patches/ssaiadserver-manifest-template.patch, the prerequisite
# our regression patch builds on). Verification is pure code-level (see tests/test.sh) — no live
# server is required, so there is no restart verb or CMD process for this task.
#
# Build context is the channelforge-world repo root (run scripts/vendor-source.sh first so
# vendor/ exists).

FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl patch ca-certificates gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── ChannelForge API ──────────────────────────────────────────────────────────────────────
WORKDIR /app
COPY vendor/apps/api /app
COPY vendor/packages /packages

COPY tasks/task-03-org-scoped-origin-drift/setup/regression-channelforge.patch /opt/world-patches/
RUN patch -p1 < /opt/world-patches/regression-channelforge.patch

RUN pip install --no-cache-dir -e /packages/media-engine \
    && pip install --no-cache-dir -e ".[dev]"

# ── ssaiadserver data-plane ───────────────────────────────────────────────────────────────
WORKDIR /ssai
COPY vendor/ssaiadserver/package.json vendor/ssaiadserver/package-lock.json* \
     vendor/ssaiadserver/tsconfig.base.json vendor/ssaiadserver/tsconfig.json ./
COPY vendor/ssaiadserver/packages ./packages

COPY world/patches/ssaiadserver-manifest-template.patch /opt/world-patches/
RUN patch -p1 < /opt/world-patches/ssaiadserver-manifest-template.patch
COPY tasks/task-03-org-scoped-origin-drift/setup/regression-ssaiadserver.patch /opt/world-patches/
RUN patch -p1 < /opt/world-patches/regression-ssaiadserver.patch

RUN npm install
RUN npm run build

WORKDIR /app
CMD ["sleep", "infinity"]
