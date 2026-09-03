# Bug report: org-scoped origin helper drifted between ChannelForge and the SSAI data-plane

We're rolling out **optional** organization-scoped origin paths, so two orgs can eventually
share an origin edge without colliding. This is still in progress and opt-in: it is implemented
as a capability in two low-level helper functions, one on each side, and **nothing else in
either codebase calls them with org scoping turned on yet**. Existing callers that don't pass an
org must keep behaving exactly as they do today — do not change that behavior or touch those
call sites.

The two helpers were written against the same design doc, and their org-scoped output doesn't
actually match each other. There are two independent, unrelated bugs to find — one in each
helper's own logic — not a wiring/integration gap:

- **ChannelForge, `/app/app/services/fast.py`, `origin_urls()`.** When `org_id` is given, look
  only at what this function itself returns and compare it against what it returns when
  `org_id` is omitted. Nothing outside this function needs to change.
- **SSAI ad server, `/ssai/packages/data-plane/src/origin.ts`, the `OriginClient` URL-building
  logic.** When an org id is configured, look only at the URL this class itself builds. Nothing
  outside this file needs to change.

What "correct" looks like: given the **same** organization id, channel/output id, and origin
base URL, the path `origin_urls()` computes and the path `OriginClient` requests must be
byte-identical, with the org id at the same position in both.

Find the drift in each of these two helpers and fix it there. This task is graded by each
service's own code directly (no live server needs to be running to verify your fix) — you do
not need to restart anything, but you may if it helps you test manually. Do not modify anything
under `tests/`, and do not modify any code outside the two helpers named above (in particular,
do not wire org scoping into any caller of `origin_urls()` or into how `OriginClient` is
constructed — that wiring is a separate, future change and is out of scope here).
