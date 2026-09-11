#!/bin/bash
# The agent's explicit restart verb for the SSAI creative worker.
set -euo pipefail
cd /ssai
npm run build
supervisorctl -c /etc/supervisor/supervisord.conf restart ssai-creative-worker
