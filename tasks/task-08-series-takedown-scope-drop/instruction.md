# Bug report: an emergency takedown placed on a series doesn't stop its episodes

A rights holder placed an emergency takedown scoped to an entire series after discovering a
licensing problem with the whole run, not just one episode. They've since found that individual
episodes of that series are still coming back as eligible to air — the takedown clearly succeeded
(it shows as active, and taking it down at the individual-episode level works fine), but scoping it
to the series instead doesn't actually block the series' own member episodes.

This isn't about how takedowns are placed, previewed, or lifted — all of that is working. It's
specifically that an *active, series-scoped* takedown fails to block an asset that belongs to that
series, even though asset-scoped takedowns block correctly and the system clearly has a concept of
a series-scoped takedown (placing one succeeds, and it's reported as active).

Find and fix the defect. When you believe the fix is correct:

1. Restart the API (`restart-api`) so the running service reflects your change.
2. Leave the fix as a normal code change — do not modify anything under `tests/`.

Do not modify the test suite, CI configuration, or any files outside ChannelForge's application
source. Your fix should be minimal and targeted at the actual defect.
