#!/usr/bin/env bash
# Verifier. Confirmed real defect (see docs/ecosystem.md): detectAvails correlates a DATERANGE
# tag's ID to whichever avail is open using duration-agnostic logic that doesn't distinguish a
# DATERANGE-OUT (opens a break) from a DATERANGE-IN (closes one). When two breaks are scheduled
# back-to-back with no gap, both breaks' cue tags land in the same origin segment's tag block
# (confirmed against ChannelForge's real worker/origin.py: `daterange_tags` for one segment are all
# rendered together, immediately before that segment's single #EXTINF/URI line) — the closing
# DATERANGE-IN of the first break sets a "current block id" that then leaks forward onto the
# second break's open avail, because the code only fills externalBreakId when it's still undefined
# instead of always trusting the most recent DATERANGE-OUT.
#
# All 10 pre-existing avails.test.ts cases (rewritten here verbatim from current pristine source,
# not reduced) plus one new case built from real ChannelForge output — worker/scte35.py's actual
# cue_out/cue_in/daterange_out/daterange_in for two adjacent 30s breaks with zero gap, exactly as
# worker/origin.py would render them into one segment's tag block. This is the real regression
# behind the bug report, not a hand-waved fixture. packages/core/src/scte.test.ts (the marker
# parser's own pristine suite) is also run unmodified as a second regression-safety plane, since a
# correct fix plausibly touches the parser (to distinguish DATERANGE-OUT from DATERANGE-IN) as well
# as the correlation logic in avails.ts.
set -euo pipefail

mkdir -p /logs/verifier
cd /app

# Anti-gaming: run with an explicit --config pointing outside /app, so any vitest.config.*
# (+ setupFiles) the agent's own patch may have left in the repo — e.g. one that monkey-patches
# expect.extend() so every assertion reports pass:true, confirmed to defeat this grader
# otherwise — is never auto-discovered. This config carries no setupFiles of its own.
cat > /tmp/trusted.vitest.config.mjs <<'CONFIG'
export default { test: {} };
CONFIG

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

  it("captures the DATERANGE ID as externalBreakId (real ChannelForge order: CUE-OUT then DATERANGE)", () => {
    const m = manifest([
      "#EXT-X-MEDIA-SEQUENCE:200",
      "#EXTINF:6.000,",
      "s200.ts",
      "#EXT-X-CUE-OUT:90",
      '#EXT-X-DATERANGE:ID="BRK-a11e5310-0003",PLANNED-DURATION=90,SCTE35-OUT=0xFC30',
      "#EXT-X-PROGRAM-DATE-TIME:2026-08-29T12:15:00.000Z",
      "#EXTINF:6.000,",
      "slate.ts",
      "#EXT-X-CUE-IN",
    ]);
    const avails = detectAvails(m, "channel_yoga");
    expect(avails).toHaveLength(1);
    expect(avails[0]!.externalBreakId).toBe("BRK-a11e5310-0003");
  });

  it("captures the id when the producer emits DATERANGE before CUE-OUT in the same block", () => {
    const m = manifest([
      "#EXT-X-MEDIA-SEQUENCE:0",
      '#EXT-X-DATERANGE:ID="BRK-xyz-0001",PLANNED-DURATION=30,SCTE35-OUT=0xFC',
      "#EXT-X-CUE-OUT:30",
      "#EXTINF:6.000,",
      "slate.ts",
      "#EXT-X-CUE-IN",
    ]);
    expect(detectAvails(m, "ch")[0]!.externalBreakId).toBe("BRK-xyz-0001");
  });

  it("leaves externalBreakId undefined when the origin carried no DATERANGE id", () => {
    const m = manifest(["#EXT-X-MEDIA-SEQUENCE:0", "#EXT-X-CUE-OUT:30", "#EXTINF:6.000,", "slate.ts", "#EXT-X-CUE-IN"]);
    expect(detectAvails(m, "ch")[0]!.externalBreakId).toBeUndefined();
  });

  it("does not leak one break's id onto a later break that has none", () => {
    const m = manifest([
      "#EXT-X-MEDIA-SEQUENCE:0",
      "#EXT-X-CUE-OUT:30",
      '#EXT-X-DATERANGE:ID="BRK-first",SCTE35-OUT=0xFC',
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
    expect(avails).toHaveLength(2);
    expect(avails[0]!.externalBreakId).toBe("BRK-first");
    expect(avails[1]!.externalBreakId).toBeUndefined();
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

  it("does not leak the first break's id onto a second break scheduled back-to-back in the same segment tag block (worker/scte35.py + worker/origin.py output, not a hand-built fixture)", () => {
    // Two real 30s breaks, back-to-back with zero gap (break B's out instant equals break A's in
    // instant), rendered exactly as worker/origin.py's render_media_playlist would: all of one
    // segment's daterange_tags (both breaks' cue-in and cue-out pairs) precede its single #EXTINF/
    // URI line, since ChannelForge's CueScheduler.tags_for_window can return tags for multiple
    // cues in one call and origin.py attaches them all to whichever segment covers that window.
    const m = manifest([
      "#EXT-X-MEDIA-SEQUENCE:0",
      "#EXT-X-CUE-OUT:30.000",
      '#EXT-X-DATERANGE:ID="BRK-a1b2c3d4-0000",START-DATE="2026-09-05T10:00:30.000Z",PLANNED-DURATION=30.000,SCTE35-OUT=0xFC302000000000000000FFF00F05303030307FFFFE002932E00000000000004F543EF2',
      "#EXTINF:6.000,",
      "s0.ts",
      "#EXTINF:6.000,",
      "s1.ts",
      "#EXTINF:6.000,",
      "s2.ts",
      "#EXTINF:6.000,",
      "s3.ts",
      "#EXTINF:6.000,",
      "s4.ts",
      "#EXT-X-CUE-IN",
      '#EXT-X-DATERANGE:ID="BRK-a1b2c3d4-0000",START-DATE="2026-09-05T10:01:00.000Z",SCTE35-IN=0xFC301B00000000000000FFF00A05303030307F5F00000000000011995BBA',
      "#EXT-X-CUE-OUT:30.000",
      '#EXT-X-DATERANGE:ID="BRK-a1b2c3d4-0001",START-DATE="2026-09-05T10:01:00.000Z",PLANNED-DURATION=30.000,SCTE35-OUT=0xFC302000000000000000FFF00F05303030317FFFFE002932E000000000000008A3F033',
      "#EXTINF:6.000,",
      "s5.ts",
      "#EXTINF:6.000,",
      "s6.ts",
      "#EXTINF:6.000,",
      "s7.ts",
      "#EXTINF:6.000,",
      "s8.ts",
      "#EXTINF:6.000,",
      "s9.ts",
      "#EXT-X-CUE-IN",
      '#EXT-X-DATERANGE:ID="BRK-a1b2c3d4-0001",START-DATE="2026-09-05T10:01:30.000Z",SCTE35-IN=0xFC301B00000000000000FFF00A05303030317F5F000000000000E399F1DC',
    ]);
    const avails = detectAvails(m, "channel_food");
    expect(avails).toHaveLength(2);
    expect(avails[0]!.externalBreakId).toBe("BRK-a1b2c3d4-0000");
    expect(avails[1]!.externalBreakId).toBe("BRK-a1b2c3d4-0001");
  });

  it("does not leak ids across a longer, randomized run of back-to-back breaks (fresh ids/durations/ordering each run — a fix that special-cases two breaks, hardcodes an id, or relies on the position/count of DATERANGE lines rather than SCTE35-OUT/SCTE35-IN must fail this)", () => {
    const breakCount = 3 + Math.floor(Math.random() * 3); // 3..5 breaks, chained with zero gap
    const ids = Array.from({ length: breakCount }, () => `BRK-${Math.random().toString(36).slice(2, 10)}`);
    const durations = Array.from({ length: breakCount }, () => 15 + Math.floor(Math.random() * 46)); // 15..60s
    // Real producers vary which comes first in a block; DATERANGE-IN's own placement relative to
    // CUE-IN is fixed (CUE-IN always closes first — that's what real worker/origin.py emits), but
    // whether a given break's DATERANGE-OUT precedes or follows its CUE-OUT is randomized per break,
    // since avails.ts must already support both orderings independent of this bug.
    const daterangeBeforeCueOut = ids.map(() => Math.random() < 0.5);

    const lines: string[] = ["#EXT-X-MEDIA-SEQUENCE:0"];
    for (let b = 0; b < breakCount; b++) {
      const id = ids[b]!;
      const duration = durations[b]!;
      const outTags = [
        `#EXT-X-CUE-OUT:${duration.toFixed(3)}`,
        `#EXT-X-DATERANGE:ID="${id}",PLANNED-DURATION=${duration.toFixed(3)},SCTE35-OUT=0xFC`,
      ];
      if (daterangeBeforeCueOut[b]) outTags.reverse();
      lines.push(...outTags);
      // A handful of content segments inside the break itself.
      const segCount = 2 + Math.floor(Math.random() * 3);
      for (let s = 0; s < segCount; s++) {
        lines.push("#EXTINF:6.000,", `b${b}s${s}.ts`);
      }
      lines.push("#EXT-X-CUE-IN", `#EXT-X-DATERANGE:ID="${id}",SCTE35-IN=0xFC`);
      // Zero gap: the next break's CUE-OUT follows immediately, no #EXTINF/URI line in between —
      // this is what actually happens whenever worker/origin.py attaches multiple cues' tags to
      // one covering segment (see the fixed-fixture case above for the real-function version).
    }

    const avails = detectAvails(manifest(lines), "channel_food");
    expect(avails).toHaveLength(breakCount);
    for (let b = 0; b < breakCount; b++) {
      expect(avails[b]!.externalBreakId).toBe(ids[b]);
      expect(avails[b]!.declaredDuration).toBe(durations[b]);
    }
    // Every avail's producer id is distinct — no break's delivery can reconcile against another's.
    expect(new Set(avails.map((a) => a.externalBreakId)).size).toBe(breakCount);
  });
});
TESTFILE

if npx vitest run --config /tmp/trusted.vitest.config.mjs packages/data-plane/src/avails.test.ts packages/core/src/scte.test.ts > /logs/verifier/vitest.log 2>&1; then
  success=1.0
  success_int=1
else
  success=0.0
  success_int=0
fi

# NOTE: correct_diagnosis/policy_compliance/side_effect_safety are placeholders (fixed at 1.0),
# same as task-01/02 — no automated side-effect-safety check exists yet in this world.
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
