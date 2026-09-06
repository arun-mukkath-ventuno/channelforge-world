# Bug report: back-to-back ad breaks get the wrong producer break id

A partner running channels with back-to-back ad breaks — one break ending at the exact instant the
next one begins, with no regular programming in between — is seeing broken per-break
reconciliation, but only on those specific breaks. Isolated breaks (anything with even a few
seconds of ordinary content before or after) reconcile correctly every time.

What they're seeing: when two breaks are scheduled with zero gap between them, the *second*
break's delivery data sometimes gets attributed to the *first* break's producer id instead of its
own. The dashboard shows impressions/fill against the wrong break, and the break that actually ran
shows no delivery data at all — as if it were never signalled.

They've confirmed the origin is emitting cue markers correctly for both breaks (checked directly
against the origin's own logs) — the fault isn't upstream of us.

Find and fix the defect. Do not weaken support for any marker syntax already handled today. When
you believe the fix is correct, restart whichever service needs it so the running system reflects
your change.

Do not modify the test suite, CI configuration, or any files outside this service's application
source. Your fix should be minimal and targeted at the actual defect.
