#!/usr/bin/env bash
# Bakes the "Yoga & You" fixture into a standalone Postgres image
# (channelforge-world-db:yoga-and-you) so reset = recreate the container from that image,
# with no seed script running at trial time.
#
# Steps: boot a throwaway world stack -> migrate -> seed -> `docker commit` the postgres
# container into a new tagged image -> tear the throwaway stack down.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAG="channelforge-world-db:yoga-and-you"
COMPOSE="docker compose -f $ROOT/world/docker-compose.yaml -p world-bake"

cleanup() {
  $COMPOSE down -v >/dev/null 2>&1 || true
}
trap cleanup EXIT

"$ROOT/scripts/vendor-source.sh"

echo "==> booting throwaway world stack"
$COMPOSE up -d --build

echo "==> running migrations"
$COMPOSE exec -T main bash -c "cd /app && alembic upgrade head"

echo "==> seeding Yoga & You fixture"
CONTAINER_MAIN="$($COMPOSE ps -q main)"
docker cp "$ROOT/scripts/seed_fixture.py" "$CONTAINER_MAIN:/opt/seed_fixture.py"
$COMPOSE exec -T main python3 /opt/seed_fixture.py

echo "==> stopping postgres cleanly before snapshotting (avoid mid-write commit)"
CONTAINER_PG="$($COMPOSE ps -q postgres)"
docker stop "$CONTAINER_PG"

echo "==> committing seeded postgres container -> $IMAGE_TAG"
docker commit "$CONTAINER_PG" "$IMAGE_TAG"

echo "==> done: $IMAGE_TAG"
docker images "$IMAGE_TAG"
