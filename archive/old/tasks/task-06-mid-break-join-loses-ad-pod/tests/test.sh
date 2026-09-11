#!/usr/bin/env bash
# Verifier. Confirmed real defect (see docs/ecosystem.md): detectAvails only recognizes an avail
# when both its opening (CUE-OUT/DATERANGE-OUT) and closing (CUE-IN/DATERANGE-IN) tags are present
# in the fetched origin window. ChannelForge's live origin window is a fixed segment count, so a
# break's opening tag ages out of that window before its closing tag does, for a span of time equal
# to the break's own duration, right after every break. A session whose *first* manifest request
# for that break lands during that trailing span never gets an Avail at all — the manifest hot path
# has no id to key a decision or a pod-cache lookup on — so it falls through to raw, unstitched
# origin content, even for a session that was already decided a pod moments earlier and simply
# reconnected. Confirmed against ChannelForge's real worker/origin.py (`daterange_tags` for one
# segment window render together, including a break's closing DATERANGE-IN, regardless of whether
# its own opening tag is still present) and worker/cue_schedule.py's real tag emission order
# (CUE-IN before DATERANGE-IN).
#
# Two verifier files, both new (neither exists in pristine ssaiadserver — this behavior was never
# covered before this task, so this task authors the real test suite for it going forward, same
# discipline as task-02):
#   - avails.test.ts: pristine's 10 existing cases (verbatim) plus new unit cases for the
#     "headless avail" detection itself, built from real worker/origin.py + worker/cue_schedule.py
#     output (not hand-typed), including a full 6-line real playlist header to catch a fix that
#     hardcodes how many header lines to skip.
#   - server.test.ts: an integration-level test exercising the full manifest hot path
#     (buildServer + MemoryPodCache + MemoryObjectStore + app.inject, matching the existing
#     control-plane/server.test.ts pattern) — two sequential requests for the same session, the
#     second with the origin window shifted so only the headless tail remains. Asserts the SAME
#     decided ad gets reattached (not a fresh, different re-decision, and not zero ads).
set -euo pipefail

mkdir -p /logs/verifier
cd /app

# Anti-gaming (carried forward from task-05, where this was confirmed to be a real, exploitable
# hole): run with an explicit --config pointing outside /app, so any vitest.config.* (+
# setupFiles) the agent's own patch may have left in the repo is never auto-discovered.
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

  it("recovers a break whose opening tag has already scrolled out of the window (real worker/origin.py + worker/cue_schedule.py output: full 6-line playlist header, CUE-IN before its DATERANGE-IN)", () => {
    const m = manifest([
      "#EXTM3U",
      "#EXT-X-VERSION:7",
      "#EXT-X-INDEPENDENT-SEGMENTS",
      "#EXT-X-TARGETDURATION:6",
      "#EXT-X-MEDIA-SEQUENCE:0",
      "#EXT-X-DISCONTINUITY-SEQUENCE:0",
      "#EXTINF:6.000,",
      "s200.ts",
      "#EXTINF:6.000,",
      "s201.ts",
      "#EXT-X-CUE-IN",
      '#EXT-X-DATERANGE:ID="BRK-old-0009",START-DATE="1970-01-01T00:00:12.000Z",SCTE35-IN=0xFC301B00000000000000FFF00A05303030397F5F0000000000006DDBF2E9',
      "#EXTINF:6.000,",
      "s202.ts",
    ]);
    const avails = detectAvails(m, "channel_food");
    expect(avails).toHaveLength(1);
    expect(avails[0]!.externalBreakId).toBe("BRK-old-0009");
    // Only the visible portion (2 segments before the CUE-IN) counts — not any assumed full length.
    expect(avails[0]!.measuredDuration).toBe(12);
    // The playlist header (6 lines) must still be intact — the avail's region starts after it,
    // not at line 0 (which would mean the header itself got replaced/discarded when stitched).
    expect(avails[0]!.startLine).toBe(6);
  });

  it("ignores a CUE-IN that never gets a DATERANGE id at all (no producer break id to recover — same fallback as any avail with no DATERANGE)", () => {
    const m = manifest([
      "#EXT-X-MEDIA-SEQUENCE:0",
      "#EXTINF:6.000,",
      "s0.ts",
      "#EXT-X-CUE-IN",
      "#EXTINF:6.000,",
      "s1.ts",
    ]);
    expect(detectAvails(m, "ch")).toEqual([]);
  });

  it("does not treat a CUE-IN closing a normally-opened avail as a headless one, even mid-manifest", () => {
    const m = manifest([
      "#EXT-X-MEDIA-SEQUENCE:0",
      "#EXT-X-CUE-OUT:12",
      '#EXT-X-DATERANGE:ID="BRK-normal",PLANNED-DURATION=12,SCTE35-OUT=0xFC',
      "#EXTINF:6.000,",
      "a.ts",
      "#EXTINF:6.000,",
      "b.ts",
      "#EXT-X-CUE-IN",
      '#EXT-X-DATERANGE:ID="BRK-normal",SCTE35-IN=0xFC',
    ]);
    const avails = detectAvails(m, "ch");
    expect(avails).toHaveLength(1);
    // Must keep the ordinary sequence-derived id, not the break-id fallback a headless avail uses.
    expect(avails[0]!.opportunityId).toBe("opp_ch_0");
  });
});
TESTFILE

cat > packages/data-plane/src/server.test.ts <<'TESTFILE'
import { describe, it, expect } from "vitest";
import { MemoryPodCache } from "@ssai/persistence";
import { MemoryObjectStore } from "@ssai/storage";
import { signSession } from "@ssai/core";
import { buildServer } from "./server.js";

const SECRET = "test-secret";

interface FakeOrigin {
  manifest: string;
  fetchMediaPlaylist(): Promise<{ body: string; fromCache: boolean; stale: boolean }>;
  originUrlFor(): string;
}

function fakeOrigin(initial: string): FakeOrigin {
  return {
    manifest: initial,
    async fetchMediaPlaylist() {
      return { body: this.manifest, fromCache: false, stale: false };
    },
    originUrlFor() {
      return "http://origin.example/channel_food/index.m3u8";
    },
  };
}

// Real worker/origin.py + worker/cue_schedule.py output for a 12s break (id BRK-mid-0004),
// segment window 100-102: opening tags visible, closing tags visible (a normal, healthy fetch).
const MANIFEST_CUE_OUT_VISIBLE = [
  "#EXTM3U",
  "#EXT-X-MEDIA-SEQUENCE:100",
  "#EXT-X-CUE-OUT:12.000",
  '#EXT-X-DATERANGE:ID="BRK-mid-0004",PLANNED-DURATION=12.000,SCTE35-OUT=0xFC',
  "#EXTINF:6.000,",
  "s100.ts",
  "#EXTINF:6.000,",
  "s101.ts",
  "#EXT-X-CUE-IN",
  '#EXT-X-DATERANGE:ID="BRK-mid-0004",SCTE35-IN=0xFC',
  "#EXTINF:6.000,",
  "s102.ts",
].join("\n");

// Same break, window shifted so the opening tags have scrolled out — only the headless tail
// (still the same closing id) and its trailing segment remain.
const MANIFEST_HEADLESS_TAIL = [
  "#EXTM3U",
  "#EXT-X-MEDIA-SEQUENCE:100",
  "#EXTINF:6.000,",
  "s100.ts",
  "#EXTINF:6.000,",
  "s101.ts",
  "#EXT-X-CUE-IN",
  '#EXT-X-DATERANGE:ID="BRK-mid-0004",SCTE35-IN=0xFC',
  "#EXTINF:6.000,",
  "s102.ts",
].join("\n");

async function seedCreative(store: MemoryObjectStore, id: string) {
  await store.put(`creatives/${id}/${id}.m3u8`, `#EXTM3U\n#EXTINF:6.000,\n${id}_seg0.ts\n#EXTINF:6.000,\n${id}_seg1.ts\n`);
}

describe("data-plane manifest hot path — mid-break join/reconnect (PRD §41 extension)", () => {
  it("reattaches the same decided pod once a break's opening tag ages out of the window, instead of falling back to raw origin or re-deciding", async () => {
    const store = new MemoryObjectStore();
    await seedCreative(store, "cr-first");
    await seedCreative(store, "cr-second");

    // A decider that returns a DIFFERENT creative each call it's actually invoked with — so any
    // fix that just re-decides on every request (rather than genuinely reattaching the cached
    // decision) is caught by the ad changing between requests, not just by a call counter.
    let decideCalls = 0;
    const creativeIds = ["cr-first", "cr-second"];
    const decider = {
      async decide() {
        const id = creativeIds[decideCalls] ?? "cr-second";
        decideCalls++;
        return [{ type: "ad" as const, creativeId: id, duration: 12, position: 0, startOffset: 0, endOffset: 12 }];
      },
    };

    const origin = fakeOrigin(MANIFEST_CUE_OUT_VISIBLE);
    const podCache = new MemoryPodCache();
    const app = buildServer({ podCache, origin, store, decider, sessionSecret: SECRET, logger: false });
    const token = signSession("sess-reconnect", "channel_food", SECRET);
    const url = `/v1/hls/${token}/channel_food/index.m3u8`;

    const res1 = await app.inject({ method: "GET", url });
    expect(res1.statusCode).toBe(200);
    expect(res1.headers["x-ssai-stitched"]).toBe("1");
    expect(res1.body).toContain("cr-first");

    // Window shifts: the opening tags scroll out, only the headless tail remains. Same session.
    origin.manifest = MANIFEST_HEADLESS_TAIL;
    const res2 = await app.inject({ method: "GET", url });
    expect(res2.statusCode).toBe(200);
    expect(res2.headers["x-ssai-stitched"]).toBe("1");
    // The SAME ad must reattach — not raw origin passthrough, and not a fresh, different decision.
    expect(res2.body).toContain("cr-first");
    expect(res2.body).not.toContain("cr-second");
    expect(res2.body).not.toContain("s100.ts"); // raw origin segment would mean nothing was stitched
    expect(decideCalls).toBe(1);
  });

  it("still decides fresh (does not crash or wrongly cache) for a session that never saw this break's opening tag at all", async () => {
    const store = new MemoryObjectStore();
    await seedCreative(store, "cr-new");
    let decideCalls = 0;
    const decider = {
      async decide() {
        decideCalls++;
        return [{ type: "ad" as const, creativeId: "cr-new", duration: 12, position: 0, startOffset: 0, endOffset: 12 }];
      },
    };
    const origin = fakeOrigin(MANIFEST_HEADLESS_TAIL);
    const podCache = new MemoryPodCache();
    const app = buildServer({ podCache, origin, store, decider, sessionSecret: SECRET, logger: false });
    const token = signSession("sess-brand-new", "channel_food", SECRET);

    const res = await app.inject({ method: "GET", url: `/v1/hls/${token}/channel_food/index.m3u8` });
    expect(res.statusCode).toBe(200);
    expect(res.headers["x-ssai-stitched"]).toBe("1");
    expect(res.body).toContain("cr-new");
    expect(decideCalls).toBe(1);
  });
});
TESTFILE

if npx vitest run --config /tmp/trusted.vitest.config.mjs \
  packages/data-plane/src/avails.test.ts \
  packages/data-plane/src/server.test.ts \
  packages/data-plane/src/stitch.test.ts \
  packages/data-plane/src/media.test.ts \
  packages/data-plane/src/origin.test.ts \
  packages/core/src/scte.test.ts \
  > /logs/verifier/vitest.log 2>&1; then
  success=1.0
  success_int=1
else
  success=0.0
  success_int=0
fi

# NOTE: correct_diagnosis/policy_compliance/side_effect_safety are placeholders (fixed at 1.0),
# same as task-01/02/05 — no automated side-effect-safety check exists yet in this world.
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
