#!/bin/bash
# The agent's explicit restart verb for fast-world-tv. Next.js production mode requires a build
# step, so this folds `next build` into the restart itself — still exactly one command, no
# fallback path.
set -euo pipefail
cd /fastweb
pnpm build
supervisorctl -c /etc/supervisor/supervisord.conf restart fast-web
