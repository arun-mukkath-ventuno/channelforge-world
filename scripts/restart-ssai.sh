#!/usr/bin/env bash
# The agent's explicit restart verb for an ssaiadserver process (control-plane or data-plane,
# selected by the SSAI_SERVICE env var already set on the container — never a flag here, so a
# task's instruction can just say "restart the SSAI control plane" without knowing internals).
# No --watch/nodemon anywhere in this world: a code edit only takes effect once this script is
# run, deliberately, by the agent. Same shape as scripts/restart-api.sh.
#
#   restart-ssai --foreground   # PID 1 entrypoint: launch the service and block
#   restart-ssai                # agent-facing: stop the running service, relaunch it
set -euo pipefail

: "${SSAI_SERVICE:?SSAI_SERVICE must be set to control-plane or data-plane}"
PIDFILE="/tmp/ssai-${SSAI_SERVICE}.pid"
ENTRYPOINT="/app/packages/${SSAI_SERVICE}/dist/server.js"

start() {
  cd /app
  # TypeScript, built to dist/ at image-build time — rebuild so an edited .ts file actually
  # takes effect. Same "restart is the only path to a live change" contract as restart-api,
  # just with a compile step folded in since this is TypeScript rather than Python.
  npm run build
  node "$ENTRYPOINT" &
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
  echo "${SSAI_SERVICE} restarted (pid $(cat "$PIDFILE"))"
fi
