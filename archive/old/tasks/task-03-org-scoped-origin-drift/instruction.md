# Bug report: org-scoped origin paths don't match between ChannelForge and the SSAI data-plane

We're rolling out **optional** organization-scoped origin paths, so two orgs can eventually
share an origin edge without colliding. This capability exists on both sides already but is
still in progress and **strictly opt-in**: today, nothing in either codebase actually turns it
on for a real request. Existing behavior — every call site and code path that doesn't request
org scoping — must keep working exactly as it does today. Do not change that behavior, and do
not add new callers that turn org scoping on somewhere it isn't already wired in — that rollout
is a separate, later piece of work and is out of scope here.

This environment gives you write access to **two services**: ChannelForge's API (`/app`) and
the SSAI ad server's data-plane (`/ssai`). Both sides implement org-scoped origin path building
against the same design, but their outputs don't actually agree with each other — there are two
independent bugs, one in each service's own org-scoping logic, not a wiring or integration gap
between the services.

What "correct" looks like: given the **same** organization id, channel/output id, and origin
base URL, the org-scoped origin path ChannelForge computes and the org-scoped origin path the
SSAI data-plane requests must be byte-identical, with the org id at the same position in both.
Behavior when no org is involved must be unaffected on both sides.

Find the drift in each service's own org-scoping logic and fix it there — you'll need to locate
where each side builds these paths yourself. This task is graded by each service's own code
directly (no live server needs to be running to verify your fix) — you do not need to restart
anything, but you may if it helps you test manually. Do not modify anything under `tests/`.
