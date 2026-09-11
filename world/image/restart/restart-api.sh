#!/bin/bash
# The agent's explicit restart verb for the ChannelForge API (docs/devops-single-image.md §8).
# supervisord owns process lifecycle in the single image, so restarting is just asking it to
# restart the one named program — no manual PID-file management needed here (that pattern from
# scripts/restart-api.sh was for the pre-Step-4 one-process-per-container compose topology; this
# script is world/image's replacement for the same verb name under supervisord).
set -euo pipefail
supervisorctl -c /etc/supervisor/supervisord.conf restart cf-api
