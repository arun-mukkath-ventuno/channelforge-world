#!/usr/bin/env bash
# Verifier. There is no pre-existing upstream test for DATERANGE avail detection (confirmed:
# avails.test.ts has zero DATERANGE cases in real ssaiadserver source) — the capability was never
# implemented, so no test for it exists to reuse the way task-01 reused a real, pre-existing
# pytest file. This script writes the real test file, augmented with one additional case built
# from real ChannelForge output (worker/scte35.py's actual daterange_out/daterange_in — see
# docs/ecosystem.md), at verify time only — after the agent's turn, outside its writable/visible
# path — and runs it. This IS the real test suite for this behavior from this point forward; it
# just didn't exist until this task authored it.
set -euo pipefail

mkdir -p /logs/verifier
cd /app

cat > packages/data-plane/src/avails.test.ts <<'TESTFILE'
import { describe, it, expect } from "vitest";
import { detectAvails } from "./avails.js";

function manifest(lines: string[]): string {
  return lines.join("\n");
}

describe("detectAvails (PRD §9, §41)", () => {
  it("derives a deterministic opportunity id from channel + media sequence", () => {
    const m = manifest([
      "#EXT-X-MEDIA-SEQUENCE:100",
      "#EXTINF:6.000,",
      "s100.ts",
      "#EXTINF:6.000,",
      "s101.ts",
      "#EXT-X-CUE-OUT:30",
      "#EXTINF:6.000,",
      "slate.ts",
      "#EXT-X-CUE-IN",
    ]);
    const avails = detectAvails(m, "channel_food");
    expect(avails).toHaveLength(1);
    // Two segments consumed (100, 101), so the avail's first segment is 102.
    expect(avails[0]).toMatchObject({
      opportunityId: "opp_channel_food_102",
      channelId: "channel_food",
      duration: 30,
      declaredDuration: 30,
      startSequence: 102,
    });
  });

  it("is stable across playlist refreshes (same avail → same id as the window slides)", () => {
    const before = manifest(["#EXT-X-MEDIA-SEQUENCE:100", "#EXTINF:6.000,", "s100.ts", "#EXT-X-CUE-OUT:30", "#EXTINF:6.000,", "slate.ts", "#EXT-X-CUE-IN"]);
    const after = manifest(["#EXT-X-MEDIA-SEQUENCE:101", "#EXT-X-CUE-OUT:30", "#EXTINF:6.000,", "slate.ts", "#EXT-X-CUE-IN"]);
    const a = detectAvails(before, "ch")[0]!;
    const b = detectAvails(after, "ch")[0]!;
    expect(a.opportunityId).toBe(b.opportunityId); // opp_ch_101 in both
  });

  it("falls back to measured duration when the marker duration is invalid (PRD §41)", () => {
    const m = manifest([
      "#EXT-X-MEDIA-SEQUENCE:0",
      "#EXT-X-CUE-OUT:oops",
      "#EXTINF:6.000,",
      "slate1.ts",
      "#EXTINF:6.000,",
      "slate2.ts",
      "#EXT-X-CUE-IN",
    ]);
    const avails = detectAvails(m, "ch");
    expect(avails[0]!.declaredDuration).toBeUndefined();
    expect(avails[0]!.measuredDuration).toBe(12);
    expect(avails[0]!.duration).toBe(12);
  });

  it("captures PROGRAM-DATE-TIME preceding the avail", () => {
    const m = manifest([
      "#EXT-X-MEDIA-SEQUENCE:0",
      "#EXT-X-PROGRAM-DATE-TIME:2026-08-29T12:15:00.000Z",
      "#EXT-X-CUE-OUT:30",
      "#EXTINF:6.000,",
      "slate.ts",
      "#EXT-X-CUE-IN",
    ]);
    expect(detectAvails(m, "ch")[0]!.programDateTime).toBe("2026-08-29T12:15:00.000Z");
  });

  it("ignores an incomplete trailing avail (CUE-OUT with no CUE-IN yet)", () => {
    const m = manifest(["#EXT-X-MEDIA-SEQUENCE:0", "#EXT-X-CUE-OUT:30", "#EXTINF:6.000,", "slate.ts"]);
    expect(detectAvails(m, "ch")).toEqual([]);
  });

  it("detects multiple avails in one window", () => {
    const m = manifest([
      "#EXT-X-MEDIA-SEQUENCE:0",
      "#EXT-X-CUE-OUT:30",
      "#EXTINF:6.000,",
      "a.ts",
      "#EXT-X-CUE-IN",
      "#EXTINF:6.000,",
      "b.ts",
      "#EXT-X-CUE-OUT:15",
      "#EXTINF:6.000,",
      "c.ts",
      "#EXT-X-CUE-IN",
    ]);
    const avails = detectAvails(m, "ch");
    expect(avails.map((a) => a.opportunityId)).toEqual(["opp_ch_0", "opp_ch_2"]);
  });

  it("detects an avail from real ChannelForge DATERANGE cues (worker/scte35.py output, not a hand-built fixture)", () => {
    const m = manifest([
      "#EXT-X-MEDIA-SEQUENCE:0",
      "#EXT-X-DATERANGE:ID=\"brk_demo_1\",START-DATE=\"2026-01-01T00:00:00.000Z\",PLANNED-DURATION=30.000,SCTE35-OUT=0xFC302000000000000000FFF00F056D6F5F317FFFFE002932E000000000000040062A06",
      "#EXTINF:6.000,",
      "slate.ts",
      "#EXTINF:6.000,",
      "slate2.ts",
      "#EXTINF:6.000,",
      "slate3.ts",
      "#EXTINF:6.000,",
      "slate4.ts",
      "#EXTINF:6.000,",
      "slate5.ts",
      "#EXT-X-DATERANGE:ID=\"brk_demo_1\",START-DATE=\"2026-01-01T00:00:30.000Z\",SCTE35-IN=0xFC301B00000000000000FFF00A056D6F5F317F5F0000000000002ED716CB",
    ]);
    const avails = detectAvails(m, "channel_food");
    expect(avails).toHaveLength(1);
    expect(avails[0]).toMatchObject({
      opportunityId: "opp_channel_food_0",
      declaredDuration: 30,
      duration: 30,
    });
  });
});
TESTFILE

if npx vitest run packages/data-plane/src/avails.test.ts > /logs/verifier/vitest.log 2>&1; then
  success=1.0
  success_int=1
else
  success=0.0
  success_int=0
fi

# NOTE: correct_diagnosis/policy_compliance/side_effect_safety are placeholders (fixed at 1.0),
# same as task-01 — no automated side-effect-safety check exists yet in this world.
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
