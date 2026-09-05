#!/usr/bin/env bash
# Verifier. fast-world-tv ships with zero test tooling upstream (confirmed: no vitest
# devDependency, no test script in package.json) — vitest is added as an image-level
# devDependency in this task's own Dockerfile. This script writes the real test file for the
# guide's page-boundary behavior at verify time only — after the agent's turn, outside its
# writable/visible path — and runs it. The boundary used in the test is derived from the
# function's own real output (the start time of the second programme in a wide window), not a
# hardcoded clock value, so it's robust to channelSchedule's internal "anchored to today's local
# midnight" behavior.
set -euo pipefail

mkdir -p /logs/verifier
cd /app

cat > src/lib/schedule-paging.test.ts <<'TESTFILE'
import { describe, it, expect } from "vitest";
import { channelSchedule } from "./channels";

describe("channelSchedule adjacent-page boundaries (task-04)", () => {
  it("does not return the same programme on both sides of an adjacent-page boundary", () => {
    const now = Date.now();
    const to = now + 6 * 3600_000;
    const wide = channelSchedule(102, now, to);
    expect(wide.length).toBeGreaterThan(2);

    // A real programme start time, taken from the function's own output — the boundary between
    // one guide page and the next.
    const boundary = wide[1].start;

    const pageA = channelSchedule(102, now, boundary);
    const pageB = channelSchedule(102, boundary, to);

    const idsA = new Set(pageA.map((p) => p.id));
    const duplicated = pageB.filter((p) => idsA.has(p.id));
    expect(duplicated).toEqual([]);

    // The boundary programme itself must appear exactly once, on the page it starts in.
    const onA = pageA.some((p) => p.id === wide[1].id);
    const onB = pageB.some((p) => p.id === wide[1].id);
    expect(onA).toBe(false);
    expect(onB).toBe(true);
  });

  it("still returns programmes for a single non-paginated window", () => {
    const now = Date.now();
    const programs = channelSchedule(101, now, now + 3 * 3600_000);
    expect(programs.length).toBeGreaterThan(0);
  });
});
TESTFILE

if npx vitest run src/lib/schedule-paging.test.ts > /logs/verifier/vitest.log 2>&1; then
  success=1.0
  success_int=1
else
  success=0.0
  success_int=0
fi

# NOTE: correct_diagnosis/policy_compliance/side_effect_safety are placeholders (fixed at 1.0),
# same as task-01/02/03 — no automated side-effect-safety check exists yet in this world.
cat > /logs/verifier/reward.json <<JSON
{
  "task_success": $success,
  "correct_diagnosis": $success,
  "policy_compliance": 1.0,
  "side_effect_safety": 1.0
}
JSON

echo "$success_int" > /logs/verifier/reward.txt
echo "verifier: task_success=$success (see vitest.log)"
