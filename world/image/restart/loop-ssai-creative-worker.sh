#!/bin/bash
# The SSAI creative worker (packages/creative-worker) ships as one-shot CLI commands
# (prepare-creative, prepare-slate, process-pending — see packages/creative-worker/package.json)
# with no daemon entrypoint of its own. supervisord needs a long-running foreground process to
# supervise, so this wraps the pending-work poll in a loop — the supervised "program" is this
# loop, not a bespoke server process.
set -euo pipefail
cd /ssai
while true; do
  node packages/creative-worker/dist/cli/process-pending.js || true
  sleep 10
done
