#!/bin/bash
# The agent's explicit restart verb for ChannelForge's media worker.
set -euo pipefail
supervisorctl -c /etc/supervisor/supervisord.conf restart cf-media-worker
