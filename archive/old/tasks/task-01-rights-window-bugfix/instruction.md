# Bug report: content airing after rights expire mid-broadcast

A rights holder has complained that one of their programmes kept airing on a published channel
after their licensing window had already lapsed *during* the scheduled broadcast — not before it
started, during it.

ChannelForge is supposed to guarantee that a scheduled event never airs outside the asset's rights
window: this is checked both when a schedule is published and again right before a channel starts.
Something in that check has regressed — it appears to only be catching rights that have *already*
expired before the event starts, not rights that lapse partway through the event's air time.

Find the bug and fix it. When you believe the fix is correct:

1. Restart the API (`restart-api`) so the running service reflects your change.
2. Leave the fix as a normal code change — do not modify anything under `tests/`.

Do not modify the test suite, CI configuration, or any files outside ChannelForge's application
source. Your fix should be minimal and targeted at the actual defect.
