#!/bin/bash
# The agent's explicit restart verb for ChannelForge's playout worker.
set -euo pipefail
supervisorctl -c /etc/supervisor/supervisord.conf restart cf-playout-worker
