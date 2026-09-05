#!/usr/bin/env bash
# Verifier. Cross-repo test spanning both services (docs/workflow.md's cross-repo model): a new
# pytest file for ChannelForge's origin_urls() and a new vitest file for ssaiadserver's
# OriginClient, both written at verify time only (after the agent's turn, outside its
# writable/visible path), plus each side's own pre-existing relevant test file so a fix doesn't
# regress what already worked. task_success requires ALL FOUR to pass — neither repo's fix alone
# is sufficient (see docs/ecosystem.md's task-03 section for why).
set -euo pipefail

mkdir -p /logs/verifier

cat > /app/tests/test_org_scoped_origin.py <<'PYEOF'
"""New coverage for org-scoped origin_urls() (task-03) — written at verify time, not visible to
the agent while it works. Checks both the new org-scoped shape and that unscoped callers (no
org_id) are unaffected."""

from app.services import fast


def test_origin_urls_org_scoped_puts_org_before_output():
    urls = fast.origin_urls("chan-abc", org_id="org-1", base_url="http://origin.example")
    assert urls == {
        "master": "http://origin.example/org-1/chan-abc/delivery_master.m3u8",
        "media": "http://origin.example/org-1/chan-abc/delivery.m3u8",
    }


def test_origin_urls_unscoped_when_org_id_absent():
    urls = fast.origin_urls("chan-abc", base_url="http://origin.example")
    assert urls == {
        "master": "http://origin.example/chan-abc/delivery_master.m3u8",
        "media": "http://origin.example/chan-abc/delivery.m3u8",
    }
PYEOF

cd /app
if pytest tests/test_org_scoped_origin.py tests/test_fast_status.py -q > /logs/verifier/pytest.log 2>&1; then
  cf_ok=1
else
  cf_ok=0
fi

cat > /ssai/packages/data-plane/src/origin-org.test.ts <<'TSEOF'
// New coverage for org-scoped OriginClient URL building (task-03) — written at verify time, not
// visible to the agent while it works. The expected URL is the literal string ChannelForge's own
// origin_urls("chan-abc", org_id="org-1", base_url="http://origin.example") produces — both
// services must agree on it independently.
import { describe, it, expect, vi } from "vitest";
import { OriginClient } from "./origin.js";

const EXPECTED = "http://origin.example/org-1/chan-abc/delivery_master.m3u8";

describe("OriginClient org-scoped template (task-03)", () => {
  it("requests the org-scoped path, org before channel", async () => {
    const fetchImpl = vi.fn(async () => ({ ok: true, status: 200, text: async () => "#EXTM3U\n" }) as unknown as Response);
    // Simulate the deployment env this task's Dockerfile doesn't set (kept out of compose so the
    // agent can't just read it off the environment) — exercised via the same env vars origin.ts
    // itself reads. Restored afterward so this doesn't leak into other tests in the same file/run.
    const prevTemplate = process.env.CHANNELFORGE_MANIFEST_PATH_TEMPLATE;
    const prevOrg = process.env.CHANNELFORGE_ORG_ID;
    process.env.CHANNELFORGE_MANIFEST_PATH_TEMPLATE = "{org}/{channel}/delivery_master.m3u8";
    process.env.CHANNELFORGE_ORG_ID = "org-1";
    try {
      const client = new OriginClient({ baseUrl: "http://origin.example", fetchImpl });
      await client.fetchMediaPlaylist("chan-abc", "index");
      expect(fetchImpl).toHaveBeenCalledWith(EXPECTED, expect.anything());
    } finally {
      if (prevTemplate === undefined) delete process.env.CHANNELFORGE_MANIFEST_PATH_TEMPLATE;
      else process.env.CHANNELFORGE_MANIFEST_PATH_TEMPLATE = prevTemplate;
      if (prevOrg === undefined) delete process.env.CHANNELFORGE_ORG_ID;
      else process.env.CHANNELFORGE_ORG_ID = prevOrg;
    }
  });
});
TSEOF

cd /ssai
if npm run build > /logs/verifier/build.log 2>&1 && \
   npx vitest run packages/data-plane/src/origin-org.test.ts packages/data-plane/src/origin.test.ts > /logs/verifier/vitest.log 2>&1; then
  ssai_ok=1
else
  ssai_ok=0
fi

if [[ "$cf_ok" == "1" && "$ssai_ok" == "1" ]]; then
  success=1.0
  success_int=1
else
  success=0.0
  success_int=0
fi

# NOTE: correct_diagnosis/policy_compliance/side_effect_safety are placeholders (fixed at 1.0),
# same as task-01/task-02 — no automated side-effect-safety check exists yet in this world.
cat > /logs/verifier/reward.json <<JSON
{
  "task_success": $success,
  "correct_diagnosis": $success,
  "policy_compliance": 1.0,
  "side_effect_safety": 1.0
}
JSON

echo "$success_int" > /logs/verifier/reward.txt
echo "verifier: task_success=$success (channelforge_ok=$cf_ok ssaiadserver_ok=$ssai_ok; see pytest.log/vitest.log)"
