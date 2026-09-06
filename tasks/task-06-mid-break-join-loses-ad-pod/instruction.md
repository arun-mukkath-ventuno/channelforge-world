# Bug report: some sessions never get an ad for part of a break

A partner reports that some viewer sessions never see any ad play during part of an ad break —
they just get the channel's own default content for that stretch instead — even though the break
was scheduled and ad-filled correctly, and other, continuously-connected viewers on the very same
channel saw a normal ad-stitched break at the same time.

They've isolated the trigger: it only affects a session whose *first* manifest request for a given
break lands after the break has already been playing for a while — a fresh tune-in, a reconnect
after a network blip, or just a client that was slow to start polling. Anything that was already
polling before the break started is unaffected, all the way through the same break.

It isn't about ad availability, eligibility, or a bad decision — a session that's affected by this
never even shows up as having tried. And it isn't only new viewers either: the *same* session,
if it had already been decided an ad for this exact break earlier (before reconnecting), still
doesn't get it back — it re-enters the break and gets nothing for whatever's left of it.

Find and fix the defect. Do not change how ads are detected or decided for the common case (a
session polling continuously through a break), and do not disable or bypass ad decisioning as a
shortcut to make the symptom go away. When you believe the fix is correct, restart whichever
service needs it so the running system reflects your change.

Do not modify the test suite, CI configuration, or any files outside this service's application
source. Your fix should be minimal and targeted at the actual defect.
