#!/usr/bin/env bash
# Verifier — real, existing test suite is the ground truth for this task, same as task-01.
# tests/test_rights_takedown.py already has test_series_takedown_blocks_member_asset covering
# exactly this scenario (series-scoped takedown must block a member asset's eligibility) — no
# synthetic test needed. Kept outside the agent's writable/visible path so it can't be edited to
# force a pass.
set -euo pipefail

mkdir -p /logs/verifier
cd /app

if pytest tests/test_rights_takedown.py -q > /logs/verifier/pytest.log 2>&1; then
  success=1.0
  success_int=1
else
  success=0.0
  success_int=0
fi

# NOTE: correct_diagnosis/policy_compliance/side_effect_safety are placeholders (fixed at 1.0),
# same as task-01/02/05/06/07 — no automated side-effect-safety check exists yet in this world.
cat > /logs/verifier/reward.json <<JSON
{
  "task_success": $success,
  "correct_diagnosis": $success,
  "policy_compliance": 1.0,
  "side_effect_safety": 1.0
}
JSON

echo "$success_int" > /logs/verifier/reward.txt
echo "verifier: task_success=$success (see pytest.log)"
