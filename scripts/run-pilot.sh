#!/usr/bin/env bash
# Step 4 pilot sweep (docs/ecosystem.md / the graceful-churning-key plan): 5 tasks x 4 models x 3
# attempts = 60 trials. Runs the two paid models first (fast, no rate risk), then the two free
# OpenRouter models at low concurrency (a single long trajectory can itself approach the 20
# req/min per-key limit, so don't stack trials on top of it).
#
# Naming: Harbor's own trial folder name is `<task-name>__<random-suffix>` — it never encodes the
# model or the attempt number. So each of the 3 attempts is run as its own `harbor run -k 1`
# invocation (still sweeping all 5 tasks via -p tasks/ in one shot), with --jobs-dir set to
# jobs/pilot-<date>/<model>/try-<n> — the path itself then carries model + try, and Harbor's own
# trial folder name carries the task, so every trial's full path unambiguously encodes
# task + model + try, e.g.:
#   jobs/pilot-2026-09-07/gpt-5.6-luna/try-2/2026-09-07__.../task-07-channel-switch-session-bleed__ab12cde/
#
# Usage: scripts/run-pilot.sh [jobs-root]
#   jobs-root defaults to jobs/pilot-<YYYY-MM-DD>
#
# Every trial's full trajectory is preserved under --jobs-dir (nothing here is scratch space, see
# the plan) — this script never deletes anything, only runs harbor and checks trial counts.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

JOBS_ROOT="${1:-jobs/pilot-$(date +%F)}"
mkdir -p "$JOBS_ROOT"

run_model() {
  local name="$1" model="$2" concurrency="$3"
  shift 3
  local extra_args=("$@")

  echo "=== $name ($model), concurrency=$concurrency ==="
  for try in 1 2 3; do
    local dir="$JOBS_ROOT/$name/try-$try"
    echo "--- $name try $try/3 -> $dir ---"
    harbor run -p tasks/ -a terminus-2 -m "$model" -k 1 -n "$concurrency" -e docker -y \
      --env-file .env --jobs-dir "$dir" ${extra_args[@]+"${extra_args[@]}"}

    local count
    count=$(find "$dir" -iname trajectory.json | wc -l | tr -d ' ')
    echo "--- $name try $try: $count/5 trajectories written ---"
    if [[ "$count" -ne 5 ]]; then
      echo "WARNING: $name try $try expected 5 trajectories (one per task), found $count." \
           "Check for exceptions (e.g. rate limits) before treating this try as complete." >&2
    fi
  done
  echo
}

# Paid models — safe to run back-to-back at higher concurrency.
run_model "gpt-5.6-luna" "openai/gpt-5.6-luna" 3
run_model "gpt-6-astra" "openai/gpt-6-astra" 3 --ak temperature=1

# Free OpenRouter models — concurrency 1 even with a topped-up key (see plan: a single long
# trajectory can itself approach the per-key rate limit).
run_model "minimax-m3" "openrouter/minimax/minimax-m3:free" 1
run_model "laguna-s-2.1" "openrouter/poolside/laguna-s-2.1:free" 1

total=$(find "$JOBS_ROOT" -iname trajectory.json | wc -l | tr -d ' ')
echo "Pilot sweep complete. $total/60 trajectories written under $JOBS_ROOT"
