#!/usr/bin/env bash
# The agent's explicit restart verb. No --reload file-watcher is used anywhere in this world:
# a code edit only takes effect once this script is run, deliberately, by the agent.
#
#   restart-api --foreground   # PID 1 entrypoint: launch uvicorn and block
#   restart-api                # agent-facing: stop the running uvicorn, relaunch it
set -euo pipefail

PIDFILE=/tmp/uvicorn.pid
APP_MODULE="app.main:app"

start() {
  cd /app
  uvicorn "$APP_MODULE" --host 0.0.0.0 --port 8000 &
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
  # Deliberately NOT `wait`-ing on uvicorn's pid: the agent restarts uvicorn from a separate
  # `docker exec` session (see the else branch below), which kills and replaces that pid. If
  # PID 1 were blocked in `wait` on the original pid, that kill would make `wait` return and
  # this script (PID 1) would exit — taking the whole container down on the agent's first
  # restart. Looping forever keeps the container's lifetime decoupled from any one uvicorn
  # invocation.
  while true; do sleep 3600 & wait $!; done
else
  stop_if_running
  start
  echo "API restarted (pid $(cat "$PIDFILE"))"
fi
