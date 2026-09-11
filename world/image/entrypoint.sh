#!/bin/bash
# PID 1 for the single-image world. Deliberately ignores "$@" — Harbor's docker environment
# provider overrides this container's compose `command:` to `sh -c "sleep infinity"` so it can
# `docker exec` into the container at will (see docs/devops-single-image.md §9, T2.3/T2.4). If
# this entrypoint execed "$@" (or anything derived from it), that override would replace
# supervisord entirely and none of the supervised programs would ever start. Always launch
# supervisord as the container's real PID 1 regardless of what command Harbor appends.
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
