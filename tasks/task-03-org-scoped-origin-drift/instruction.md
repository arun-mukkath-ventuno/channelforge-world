# Bug report: SSAI origin fetch broken since the multi-tenant origin rollout

We've started scoping ChannelForge's origin delivery paths by organization, so two orgs can never
collide on a shared origin edge. Since that change went out, the SSAI ad-insertion layer can't
reliably find a channel's manifest anymore for any org-scoped deployment — origin fetches are
landing on the wrong path.

This environment gives you write access to **two services**: ChannelForge's API (`/app`) and the
SSAI ad server's data-plane origin client (`/ssai`). The migration was rolled out to both sides at
once and something didn't line up — you'll need to look at both to find it.

What "correct" looks like: for the same organization, channel, and origin base URL, the URL
ChannelForge's origin service computes and the URL the SSAI data-plane's origin client requests
must be the identical path, org-scoped, with the org appearing at the same position both sides
agree on.

Find the drift and fix it on both sides. This task is graded by each service's own code directly
(no live server needs to be running to verify your fix) — you do not need to restart anything, but
you may if it helps you test manually. Do not modify anything under `tests/`, and keep each fix
scoped to the service it belongs to.
