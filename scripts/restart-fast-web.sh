#!/usr/bin/env bash
# The agent's explicit restart verb for fast-world-tv. No `next dev` anywhere in this world: a
# code edit only takes effect once this script is run, deliberately, by the agent. Next.js
# production mode requires a build step, so this folds `next build` into the restart itself —
# still exactly one command, no fallback path. Same shape as scripts/restart-api.sh.
#
#   restart-fast-web --foreground   # PID 1 entrypoint: build, launch, and block
#   restart-fast-web                # agent-facing: stop the running server, rebuild, relaunch
set -euo pipefail

PIDFILE=/tmp/next-start.pid

start() {
  cd /app
  pnpm build
  pnpm start &
  echo $! > "$PIDFILE"
}

stop_if_running() {
  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill "$(cat "$PIDFILE")"
    wait "$(cat "$PIDFILE")" 2>/dev/null || true
  fi
}

if [[ "${1:-}" == "--foreground" ]]; then
  start
  # See scripts/restart-api.sh for why PID 1 loops forever instead of waiting on the child pid.
  while true; do sleep 3600 & wait $!; done
else
  stop_if_running
  start
  echo "fast-web restarted (pid $(cat "$PIDFILE"))"
fi
