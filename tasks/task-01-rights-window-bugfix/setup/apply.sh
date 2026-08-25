#!/usr/bin/env bash
# Applies this task's regression on top of the pristine app image, before the agent's turn
# starts. The app image itself is task-agnostic (pristine vendored source) — each task injects
# its own bug/gap this way, so tasks don't require separate app-image builds.
set -euo pipefail
cd /app
patch -p1 < /task/setup/regression.patch
