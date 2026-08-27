# channelforge-world db image.
#
# PGDATA is deliberately moved off /var/lib/postgresql/data: the base postgres:16 image
# declares that path as a VOLUME, and `docker commit` never captures data inside a declared
# volume (a well-known Docker behavior, confirmed the hard way while baking the Yoga & You
# fixture -- see scripts/bake-fixture-db.sh and docs/how-it-works.md). Moving PGDATA to a
# plain, non-volume path is what makes the baked-fixture pattern actually work.
FROM postgres:16
ENV PGDATA=/var/lib/postgresql/cf-data
