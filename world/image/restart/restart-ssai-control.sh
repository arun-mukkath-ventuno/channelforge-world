#!/bin/bash
# The agent's explicit restart verb for the SSAI control plane. TypeScript, built to dist/ at
# image-build time — rebuild so an edited .ts file actually takes effect, same "restart is the
# only path to a live change" contract as restart-api.
set -euo pipefail
cd /ssai
npm run build
supervisorctl -c /etc/supervisor/supervisord.conf restart ssai-control
