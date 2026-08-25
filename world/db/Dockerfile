# channelforge-world db image — currently a thin pass-through over stock Postgres.
#
# TODO (tracked in POC Task Tracker, not required by task-01): bake a synthetic tenant
# ("Yoga & You") into this image's data directory at build time, once the fixture builder
# exists, so reset = recreate the container rather than reseed at start. Per-task anomaly
# variants (when a task actually needs DB state, not just a source patch) become tags of
# this image built the same way.

FROM postgres:16
