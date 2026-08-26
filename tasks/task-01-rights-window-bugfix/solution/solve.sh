#!/usr/bin/env bash
# Oracle — reference fix, used only to validate the task is solvable. Never shown to the agent.
# Reversing the regression baked into the image at build time (environment/Dockerfile) IS the
# correct fix here (single-line, well-scoped).
set -euo pipefail
cd /app
patch -p1 -R < /opt/task-setup/regression.patch
restart-api
