#!/bin/bash
# Generic TCP readiness guard (docs/devops-single-image.md §8): supervisord's `priority=` only
# orders *start attempts*, not readiness, so any program with a real dependency edge must block
# on that dependency actually answering before starting — same role as the ventuno-world
# precedent's wait-for-mysql.sh, generalized to one reusable script instead of one file per
# dependency (a `nc`-based poll is identical for every TCP dependency in this world; the
# per-service "wait-for-*" identity in the tracker is expressed by how each supervisor program's
# `command=` invokes this script, not by duplicating the script per service).
#
#   wait-for-tcp.sh <host> <port> [timeout_seconds, default 60]
set -euo pipefail

host="$1"
port="$2"
timeout="${3:-60}"

elapsed=0
until (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null; do
  exec 3<&- 2>/dev/null || true
  exec 3>&- 2>/dev/null || true
  elapsed=$((elapsed + 1))
  if [[ "$elapsed" -ge "$timeout" ]]; then
    echo "wait-for-tcp: timed out waiting for ${host}:${port} after ${timeout}s" >&2
    exit 1
  fi
  sleep 1
done
exec 3<&- 2>/dev/null || true
exec 3>&- 2>/dev/null || true
echo "wait-for-tcp: ${host}:${port} is ready"
