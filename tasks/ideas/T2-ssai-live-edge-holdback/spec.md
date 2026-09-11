# T2 · `ssai-live-edge-holdback` — task idea spec

Status: **idea stage, Stage 1 flagged — "Needs more work," not passed to Stage 2/3**. See
[`evaluation.md`](evaluation.md) for why.

Catalogue source: `docs/fast-world-bench.md`, T2 of the T1-T10 idea catalogue
(`docs/mvp-scope.md` Phase 3 backlog). GitHub issue-tracked at
[#62](https://github.com/ventuno-worlds/channelforge-world/issues/62) (Stage 1),
[#63](https://github.com/ventuno-worlds/channelforge-world/issues/63) (Stage 2),
[#64](https://github.com/ventuno-worlds/channelforge-world/issues/64) (Stage 3).

## Repo / files

- **Repo:** `ssaiadserver`
- **Files:** `packages/data-plane/src/origin-rewrite.ts` (implementation), wired in
  `packages/data-plane/src/server.ts`
- **May edit:** `packages/data-plane/src/origin-rewrite.ts`, `packages/data-plane/src/server.ts`

## The break (Phase 4 build step, not yet applied)

`holdBackManifest` stubbed to return the body unchanged, its call site removed from `server.ts`,
and the `SSAI_LIVE_EDGE_HOLDBACK` env knob left unread.

## Idea description, as scored at Stage 1 (GH #62, verbatim)

> Implement `holdBackManifest(body, N)`: trim newest N segments with their leading tags, leave
> MEDIA-SEQUENCE untouched, no-op when too few.

## Instruction (draft, `docs/fast-world-bench.md`'s original catalogue text)

> Stitched ads sometimes don't reach the player because the origin's newest segments are served
> before the ad is ready. Serve the manifest a fixed number of segments behind the true live edge.
> Do not alter `EXT-X-MEDIA-SEQUENCE`; keep each segment's leading tags with it; no-op if there are
> fewer segments than the hold-back.

**This is exactly the finding that flagged Stage 1** — see `evaluation.md`. Both the idea
description (which names the function signature directly) and the draft instruction (which lists
all three implementation-critical invariants explicitly) hand the agent the full solution shape
before it does any discovery. Any revision needs to fix this before Stage 1 can be re-run.

## Held-out verifier (original catalogue list)

- Segment count −N.
- `MEDIA-SEQUENCE` unchanged.
- Leading tags (EXTINF, PROGRAM-DATE-TIME, DISCONTINUITY) stay attached to their segment.
- Idempotent on short input.
- N=0 is identity.

Note: these five checks are **identical, one-to-one, to the five existing test names** already in
the vendored `origin-rewrite.test.ts` — see `evaluation.md` Stage 1 for why that's a discriminating
problem, not just a coincidence.

## Anti-cheat

Assertions on output manifest structure; held-out N values.

## Budget

~180k tokens / ~45 steps.

## Tier / provenance

Core (~0.4 target `task_success`) · ssai hold-back (idea catalogue #11 in `docs/fast-world-bench.md`'s
numbering).

## Write boundary

Single-repo (`ssaiadserver` only).
