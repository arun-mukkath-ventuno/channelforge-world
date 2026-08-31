# Bug report: ad breaks never fill, avail count always zero

A partner running FAST channels through us reports that ad breaks scheduled on their channels
never actually get filled — viewers just see pass-through slate through the whole break, and
their analytics dashboard shows zero avails detected, ever, on any of their channels. This isn't
intermittent: it's every break, on every channel they have.

They've confirmed with their upstream provider (the channel origin) that breaks are genuinely
being scheduled and that cue markers are present in the live stream — their origin's own logs
show cue-out/cue-in events firing on schedule. So the breaks are real; something on our side is
just never seeing them.

The origin markers on these channels use the HLS `EXT-X-DATERANGE` cue-signalling style (as
opposed to the simpler `EXT-X-CUE-OUT`/`EXT-X-CUE-IN` style some other channel operators use).

Find why avails aren't being detected on these channels and fix it. When you believe the fix is
correct, restart whichever service needs it so the running system reflects your change. Leave the
fix as a normal code change — do not modify anything under `tests/`.

Do not modify the test suite, CI configuration, or any files outside this service's application
source. Your fix should be minimal and targeted at the actual defect.
