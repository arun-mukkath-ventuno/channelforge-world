# Bug report: same programme shows up on both sides of a guide page

A viewer paging through the FAST channel guide reported seeing the same programme listed twice —
once as the last item on one page of the guide, and again as the first item on the very next
page, for the same channel.

The guide is meant to be requested in adjacent, non-overlapping time windows (page N covers
`[t0, t1)`, page N+1 covers `[t1, t2)`, and so on) and each programme should appear on exactly
one page — the one whose window it starts in. Right now, a programme whose start time lands
exactly on a page boundary is appearing on both the page before the boundary and the page after
it.

This is a single-repo task: fast-world-tv (`/app`) is the only service you have write access to,
and the fix does not require anything outside its own application source. This is graded at the
code level (no live server needs to be running to verify your fix) — you do not need to restart
anything, but you may if it helps you test manually.

Find where the guide's time-window logic decides which programmes belong in a requested window,
and fix the boundary handling so that querying two adjacent windows never returns the same
programme in both. Do not modify anything under `tests/`, and do not change what a single,
non-paginated window request returns for programmes that don't sit on a boundary.
