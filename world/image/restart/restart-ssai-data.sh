#!/bin/bash
# The agent's explicit restart verb for the SSAI data plane. Same rebuild-then-restart contract
# as restart-ssai-control.sh — the two planes share one npm workspace build, but each has its
# own supervisor program and its own restart verb (never a shared/env-var-dispatched script,
# per AGENTS.md rule 2: exactly one named restart verb per service).
set -euo pipefail
cd /ssai
npm run build
supervisorctl -c /etc/supervisor/supervisord.conf restart ssai-data
