#!/usr/bin/env python3
"""Seed the "Yoga & You" synthetic tenant for the ChannelForge World POC.

Run *inside* the `main` container, against an already-running API (call `restart-api` first):

    docker compose exec main python3 /opt/seed_fixture.py

Mirrors the pattern already used by tests/helpers.py: real API calls (signup, collections,
programming blocks, channel, schedule generate+publish) for anything with real validation logic
worth exercising, and direct ORM inserts only for Asset/MediaVersion — the one thing this sealed
world has no real pipeline for (no ffprobe, no S3), matching how the existing test suite already
fakes media without a real probe/encode step.

Content: 10 of the asset titles below are real, taken from an internal pilot org's actual asset
library (~/Downloads/channelforge-prod-2026-08-25.sql.gz, "Ventuno Yoga" / cb4a0bac-80b0-4b3a-a739-
7b8d61b33329) — durations included. Everything else (Morning Yoga, Meditation, Bumpers, Filler
titles, and the whole collection/channel/schedule structure) is purpose-built for this fixture, not
copied from that org, which was too operationally messy (live `running` state, 24k schedule events,
craft-video content mixed in) to import wholesale.
"""

from __future__ import annotations

import sys
import uuid
from datetime import datetime, timedelta, timezone

import httpx

API = "http://localhost:8000/api"

# --- content -------------------------------------------------------------------------------

# (title, duration_seconds) -- real, from the pilot org's actual asset library.
REAL_BEGINNER = [
    ("Gentle Yoga for Complete Beginners — Full Body Beginner Yoga Flow", 1799.66),
    ("Padmasana for Beginners — Learn Lotus Pose Safely Without Knee Pain", 1482.18),
    ("Butterfly Pose (Baddha Konasana) — Yoga for Hips & Inner Thighs", 456.13),
    ("Hanumanasana (Front Splits) Step-by-Step — Safe Entry & Alignment", 456.57),
    ("Marichyasana C — Seated Spinal Twist for Deep Back Release", 489.84),
]
REAL_ADVANCED = [
    ("Learn Kakasana Safely — Crow Pose Breakdown for Beginners", 1475.05),
    ("Parsva Bakasana Deep Dive — Master This Challenging Arm Balance", 601.14),
    ("Dhanurasana (Bow Pose) Variations — How To Do Dhanurasana", 808.82),
    ("Paschimottanasana (Seated Forward Fold) — Full Tutorial & Variations", 1242.73),
    ("Sarvangasana (Shoulder Stand) — Benefits, Steps & Wall Support", 289.46),
]
# Purpose-built for this fixture, not copied from any real org.
MORNING_YOGA = [
    ("Sunrise Sun Salutations — 12-Pose Morning Flow", 620.0),
    ("Wake-Up Stretch Sequence for Stiff Mornings", 540.0),
    ("Morning Energy Flow — Vinyasa Basics", 700.0),
    ("Gentle Morning Mobility — Joints & Spine", 480.0),
    ("Rise & Breathe — Morning Pranayama Warm-Up", 390.0),
    ("Morning Balance Sequence — Standing Poses", 610.0),
]
MEDITATION = [
    ("10-Minute Morning Meditation — Breath Awareness", 600.0),
    ("Body Scan Relaxation — Full-Body Release", 900.0),
    ("Evening Wind-Down Meditation", 720.0),
    ("Loving-Kindness Meditation — Guided Practice", 660.0),
    ("Stillness Practice — Silent Sit with Bells", 1200.0),
    ("Breath-Counting Meditation for Focus", 480.0),
]
BUMPERS = [
    ("Yoga & You — Channel ID Bumper", 12.0),
    ("Coming Up Next — Bumper", 8.0),
    ("Yoga & You — Welcome Bumper", 15.0),
    ("Stay Tuned — Short Bumper", 10.0),
]
FILLER = [
    ("Calm Waters — Ambient Loop", 45.0),
    ("Mountain Stillness — Ambient Loop", 60.0),
    ("Soft Morning Light — Ambient Loop", 40.0),
    ("Gentle Rain — Ambient Loop", 50.0),
]


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(dt: datetime) -> str:
    return dt.isoformat()


def main() -> None:
    client = httpx.Client(base_url=API, timeout=30.0)

    # --- org + auth (real signup, real validation) ------------------------------------------
    resp = client.post(
        "/auth/signup",
        json={
            "email": "owner@yogaandyou.example",
            "password": "supersecret123",
            "organization_name": "Yoga & You",
            "full_name": "Yoga & You Owner",
        },
    )
    if resp.status_code != 201:
        print(f"signup failed: {resp.status_code} {resp.text}", file=sys.stderr)
        sys.exit(1)
    me = resp.json()
    org = me["organizations"][0]["organization_id"]
    print(f"org created: {org}")

    # --- assets + media versions (direct ORM -- no real media pipeline in this world) -------
    # Imported here, not at module level: only valid once run inside the app container.
    from app.db import SessionLocal
    from app.models import Asset, MediaVersion, StorageConnection

    db = SessionLocal()
    conn = StorageConnection(
        organization_id=uuid.UUID(org), name="fixture-storage", bucket="yoga-and-you-fixture",
        access_key_id="fixture-key", secret_access_key_encrypted="fixture-secret-not-real",
    )
    db.add(conn)
    db.flush()

    rights_start = _now() - timedelta(days=30)
    rights_end = _now() + timedelta(days=365)

    def _make_asset(title: str, duration: float, content_type: str) -> Asset:
        asset = Asset(
            organization_id=uuid.UUID(org), title=title, content_type=content_type,
            duration_seconds=duration, enabled=True,
            rights_start=rights_start, rights_end=rights_end,
        )
        db.add(asset)
        db.flush()
        mv = MediaVersion(
            organization_id=uuid.UUID(org), asset_id=asset.id, storage_connection_id=conn.id,
            object_key=f"source/{asset.id}.mp4", is_source=True, is_available=True,
            duration_seconds=duration, compatibility_state="compatible",
            normalization_state="completed", normalized_output_key=f"normalized/{asset.id}.mp4",
        )
        db.add(mv)
        return asset

    collections: dict[str, list[Asset]] = {
        "Morning Yoga": [_make_asset(t, d, "programme") for t, d in MORNING_YOGA],
        "Beginner Sessions": [_make_asset(t, d, "programme") for t, d in REAL_BEGINNER],
        "Advanced Sessions": [_make_asset(t, d, "programme") for t, d in REAL_ADVANCED],
        "Meditation": [_make_asset(t, d, "programme") for t, d in MEDITATION],
        "Bumpers": [_make_asset(t, d, "bumper") for t, d in BUMPERS],
        "Filler": [_make_asset(t, d, "filler") for t, d in FILLER],
    }
    db.commit()
    n_assets = sum(len(v) for v in collections.values())
    print(f"assets created: {n_assets} across {len(collections)} collections")

    # --- collections + programming blocks (real API) ----------------------------------------
    collection_ids: dict[str, str] = {}
    for name, assets in collections.items():
        r = client.post(
            f"/organizations/{org}/collections",
            json={"name": name, "type": "manual", "asset_ids": [str(a.id) for a in assets]},
        )
        r.raise_for_status()
        collection_ids[name] = r.json()["id"]
    print(f"collections created: {list(collection_ids)}")

    block_ids = []
    for name in ("Morning Yoga", "Beginner Sessions", "Advanced Sessions", "Meditation"):
        r = client.post(
            f"/organizations/{org}/programming-blocks",
            json={
                "name": f"{name} Block", "source_collection_id": collection_ids[name],
                "ordering": "shuffle",
            },
        )
        r.raise_for_status()
        block_ids.append(r.json()["id"])
    print(f"programming blocks created: {len(block_ids)}")

    # --- channel (real API) ------------------------------------------------------------------
    r = client.post(f"/organizations/{org}/channels", json={"name": "Main Channel"})
    r.raise_for_status()
    channel_id = r.json()["id"]

    # default_filler_collection_id has no dedicated endpoint in the tested surface (see
    # tests/test_lifecycle.py's setup_channel) -- set directly, same as the test suite does.
    from app.models import Channel

    channel = db.get(Channel, uuid.UUID(channel_id))
    channel.default_filler_collection_id = uuid.UUID(collection_ids["Filler"])
    db.commit()
    print(f"channel created: {channel_id} (idle, not started -- no live playout in this world)")

    # --- schedule: generate + publish (real API) ---------------------------------------------
    # Start 6h in the past so some events land in the past relative to "now" -- gives the
    # as-run entries below something real to reconcile against.
    start_at = _now() - timedelta(hours=6)
    r = client.post(
        f"/organizations/{org}/channels/{channel_id}/schedule/generate",
        json={
            "start_at": _iso(start_at), "horizon_seconds": 24 * 3600, "block_ids": block_ids,
        },
    )
    r.raise_for_status()
    draft = r.json()
    print(f"schedule generated: {len(draft['events'])} events")

    r = client.post(f"/organizations/{org}/channels/{channel_id}/schedule/publish", json={})
    r.raise_for_status()
    published = r.json()
    print(f"schedule published: version {published['version_number']}")

    # --- as-run entries for the already-past portion (direct ORM) ---------------------------
    # Mirrors what the playout worker would have written -- there is no live worker in this
    # world, so this is seeded directly, same as Asset/MediaVersion above.
    from app.models import AsRunEntry, ScheduleEvent

    now = _now()
    past_events = (
        db.query(ScheduleEvent)
        .filter(ScheduleEvent.channel_id == uuid.UUID(channel_id))
        .filter(ScheduleEvent.planned_end <= now)
        .order_by(ScheduleEvent.planned_start)
        .all()
    )
    for event in past_events:
        db.add(AsRunEntry(
            organization_id=uuid.UUID(org), channel_id=uuid.UUID(channel_id),
            schedule_event_id=event.id, asset_id=event.asset_id,
            media_version_id=event.media_version_id, title=event.title,
            planned_start=event.planned_start, planned_end=event.planned_end,
            actual_start=event.planned_start, actual_end=event.planned_end,
            outcome="aired", destinations=[],
        ))
    db.commit()
    print(f"as-run entries seeded: {len(past_events)}")

    db.close()
    print("\nYoga & You fixture seeded successfully.")
    print(f"  org={org}")
    print(f"  channel={channel_id}")


if __name__ == "__main__":
    main()
