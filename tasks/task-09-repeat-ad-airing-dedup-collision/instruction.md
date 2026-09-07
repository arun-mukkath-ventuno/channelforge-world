# Bug report: a creative's second airing in the same viewing session doesn't get counted

Analytics correctly count a viewer's first play of a given ad creative during a session: an
impression, a start, each quartile, and a completion all show up on the dashboard as expected.

But if that same session later plays the *same creative* again — a perfectly normal thing to
happen, e.g. a small ad pool reusing a house/filler creative across more than one break in one
continuous viewing session — none of that second airing's events show up. Not "undercounted": the
dashboard's advertising counts (starts, quartiles, completions) simply don't move at all for the
second airing, as if the viewer never watched it. The viewer did see it, and did finish it, both
times.

This isn't a server-side dedup bug in the sense of the intended behavior breaking — genuinely
duplicate re-sends of the *same* airing's beacon (e.g. after the player's manifest refreshes
mid-break) are still supposed to collapse into one recorded event, and that must keep working.
The problem is specifically that two *different* airings of the same creative, later in the same
session, are being treated as if they were the same occurrence.

The events you send land in a separate service's ingestion endpoint, not this repo — its
deduplication logic isn't yours to change, but whatever you send has to actually line up with how
it decides two events are "the same one". A read-only copy of that service's relevant source is
available in the environment for you to check against; don't guess at its contract.

Find and fix the defect. When you believe the fix is correct, restart whichever service needs it
so the running system reflects your change.

Do not modify the test suite, CI configuration, or any files outside this service's application
source. Your fix should be minimal and targeted at the actual defect.
