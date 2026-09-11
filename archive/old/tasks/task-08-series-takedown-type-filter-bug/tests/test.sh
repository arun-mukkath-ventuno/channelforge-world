#!/usr/bin/env bash
# Verifier — real, existing test suite is the ground truth for this task, same as task-01.
# tests/test_rights_takedown.py already has test_series_takedown_blocks_member_asset covering
# exactly this scenario (series-scoped takedown must block a member asset's eligibility) — no
# synthetic test needed.
#
# Anti-gaming (confirmed via an actual manual exploit, not assumed): unlike task-05/06/07's
# vitest --config isolation, pytest always collects tests/conftest.py from the directory it's
# given regardless of any flag — there is no equivalent "point at a trusted config outside the
# repo" option. Editing tests/conftest.py to add a pytest_runtest_makereport hookwrapper that
# flips every failed test's outcome to "passed" was confirmed to turn this task's real,
# regression-broken suite into a clean "5 passed" with the bug still live. Closed the only way
# available for pytest: overwrite conftest.py and the target test file with trusted content
# immediately before running, so any edit to either (or to `tests/` module discovery via a
# planted hook) is discarded at verify time. `tests/helpers.py` and `tests/test_schedules.py`
# (imported here for shared fixtures) are not similarly pinned — a residual, lower-priority gap,
# not yet exploited or confirmed.
set -euo pipefail

mkdir -p /logs/verifier
cd /app

cat > tests/conftest.py <<'PYFILE'
"""Test fixtures: file-backed SQLite, get_db override, and client factory.

A temp-file SQLite database backs each test (not in-memory StaticPool) so that separate
sessions — the request path and eager Celery tasks — each get their own connection to the
same database, as they would in production.
"""

from __future__ import annotations

import os

# Configure a SQLite test database before importing any app module, so app.db does not
# instantiate the PostgreSQL engine (and its psycopg driver) at import time.
os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("GOOGLE_OAUTH_CLIENT_ID", "test-client-id")
os.environ.setdefault(
    "GOOGLE_OAUTH_REDIRECT_URI",
    "http://testserver/api/integrations/youtube/oauth/callback",
)

import tempfile  # noqa: E402
from collections.abc import Callable, Iterator  # noqa: E402
from pathlib import Path  # noqa: E402

import pytest  # noqa: E402
from app.db import get_db  # noqa: E402
from app.main import app  # noqa: E402
from app.models import Base  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import Session, sessionmaker  # noqa: E402


@pytest.fixture()
def engine():
    tmpdir = tempfile.mkdtemp(prefix="cf-test-db-")
    db_path = Path(tmpdir) / "test.db"
    eng = create_engine(
        f"sqlite:///{db_path}", connect_args={"check_same_thread": False}
    )
    Base.metadata.create_all(eng)
    yield eng
    eng.dispose()
    db_path.unlink(missing_ok=True)


@pytest.fixture()
def session_factory(engine) -> sessionmaker:
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


@pytest.fixture()
def fake_redis():
    """A per-test fakeredis, shared between the request path (get_redis) and the test body."""
    import fakeredis

    return fakeredis.FakeStrictRedis()


@pytest.fixture(autouse=True)
def _fake_preflight_storage_probe(monkeypatch):
    """Start preflight probes storage connections; unit tests must never hit real S3.

    Tests that exercise the failure path pass their own `storage_client_factory`.
    """

    class _OkProbe:
        def test_connection(self) -> None:
            pass

    from app.services import lifecycle

    monkeypatch.setattr(lifecycle, "build_storage_client", lambda conn: _OkProbe())


@pytest.fixture(autouse=True)
def _override_db(session_factory, engine, fake_redis) -> Iterator[None]:
    def override() -> Iterator[Session]:
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override

    from app.redis_client import get_redis

    app.dependency_overrides[get_redis] = lambda: fake_redis

    # Point app.db at the test engine too, so eager Celery tasks (which open their own
    # SessionLocal sessions) share the same in-memory database as the request path.
    import app.db as db_module

    prev_engine, prev_factory = db_module.engine, db_module.SessionLocal
    db_module.engine = engine
    db_module.SessionLocal = session_factory
    yield
    db_module.engine, db_module.SessionLocal = prev_engine, prev_factory
    app.dependency_overrides.clear()


@pytest.fixture()
def make_client() -> Iterator[Callable[[], TestClient]]:
    created: list[TestClient] = []

    def _make() -> TestClient:
        client = TestClient(app)
        created.append(client)
        return client

    yield _make
    for client in created:
        client.close()


@pytest.fixture()
def client(make_client) -> TestClient:
    return make_client()


@pytest.fixture()
def db(session_factory) -> Iterator[Session]:
    session = session_factory()
    try:
        yield session
    finally:
        session.close()
PYFILE

cat > tests/test_rights_takedown.py <<'PYFILE'
"""Emergency rights takedown (PRD 3.0 §8.3)."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

from app.models import Alert, ScheduleEvent, ScheduleVersion

from tests.helpers import first_org_id, signup
from tests.test_schedules import make_channel

_IMPORT = {
    "source_system": "cms",
    "series": {"external_reference": "SER-1", "title": "Yoga & You"},
    "episodes": [
        {"external_reference": "EP-1", "title": "Flow", "season_number": 1, "episode_number": 1,
         "genre": "Wellness", "rating": "TV-G", "short_description": "x",
         "original_air_date": "2026-01-05"},
    ],
}


def _import_asset(client, org) -> str:
    return client.post(
        f"/api/organizations/{org}/library/import", json=_IMPORT
    ).json()["rows"][0]["asset_id"]


def _agreement(client, org, *, territory="IN", channel_id=None):
    body = {"name": "deal", "partner": "samsung", "territory": territory}
    if channel_id:
        body["channel_id"] = channel_id
    return client.post(f"/api/organizations/{org}/agreements", json=body).json()["id"]


def _verdict(client, org, asset_id, agreement_id=None):
    url = f"/api/organizations/{org}/assets/{asset_id}/eligibility"
    if agreement_id:
        url += f"?agreement_id={agreement_id}"
    return client.get(url).json()


def test_takedown_blocks_and_lift_restores(client):
    org = first_org_id(signup(client))
    asset_id = _import_asset(client, org)
    agreement = _agreement(client, org)
    assert _verdict(client, org, asset_id, agreement)["verdict"] == "eligible"

    placed = client.post(
        f"/api/organizations/{org}/rights/takedowns",
        json={"scope_type": "asset", "scope_id": asset_id, "reason": "legal hold"},
    )
    assert placed.status_code == 201, placed.text
    takedown_id = placed.json()["takedown"]["id"]

    # Blocked with an agreement AND without one (takedown is absolute).
    for aid in (agreement, None):
        result = _verdict(client, org, asset_id, aid)
        assert result["verdict"] == "ineligible"
        assert any(r["code"] == "rights_takedown" for r in result["reasons"])

    lifted = client.post(f"/api/organizations/{org}/rights/takedowns/{takedown_id}/lift")
    assert lifted.status_code == 200
    assert _verdict(client, org, asset_id, agreement)["verdict"] == "eligible"


def test_takedown_reports_affected_events_and_agreements(client, db):
    org = first_org_id(signup(client))
    asset_id = _import_asset(client, org)
    channel_id = make_channel(client, org, tz="UTC")
    agreement = _agreement(client, org, channel_id=channel_id)

    # A future event in a published version that airs this asset.
    sv = ScheduleVersion(
        organization_id=uuid.UUID(org), channel_id=uuid.UUID(channel_id),
        version_number=1, status="published", published_at=datetime.now(UTC),
    )
    db.add(sv)
    db.flush()
    start = datetime.now(UTC) + timedelta(days=1)
    db.add(ScheduleEvent(
        organization_id=uuid.UUID(org), channel_id=uuid.UUID(channel_id),
        schedule_version_id=sv.id, event_type="programme", asset_id=uuid.UUID(asset_id),
        title="Flow", planned_start=start, planned_end=start + timedelta(minutes=30),
        planned_duration_seconds=1800.0,
    ))
    db.commit()

    placed = client.post(
        f"/api/organizations/{org}/rights/takedowns",
        json={"scope_type": "asset", "scope_id": asset_id, "reason": "rights pulled"},
    ).json()
    assert placed["affected"]["event_count"] == 1
    assert channel_id in placed["affected"]["channel_ids"]
    assert agreement in placed["affected"]["agreement_ids"]


def test_takedown_raises_incident(client, db):
    org = first_org_id(signup(client))
    asset_id = _import_asset(client, org)
    client.post(
        f"/api/organizations/{org}/rights/takedowns",
        json={"scope_type": "asset", "scope_id": asset_id, "reason": "x"},
    )
    alert = db.query(Alert).filter(Alert.alert_type == "rights_takedown").one()
    assert alert.severity == "critical" and alert.status == "open"


def test_series_takedown_blocks_member_asset(client, db):
    from app.models import Asset

    org = first_org_id(signup(client))
    asset_id = _import_asset(client, org)
    series_id = db.get(Asset, uuid.UUID(asset_id)).series_id
    assert series_id is not None

    client.post(
        f"/api/organizations/{org}/rights/takedowns",
        json={"scope_type": "series", "scope_id": str(series_id), "reason": "series pulled"},
    )
    result = _verdict(client, org, asset_id)
    assert result["verdict"] == "ineligible"
    assert any(r["code"] == "rights_takedown" for r in result["reasons"])


def test_invalid_scope_type_rejected(client):
    org = first_org_id(signup(client))
    asset_id = _import_asset(client, org)
    resp = client.post(
        f"/api/organizations/{org}/rights/takedowns",
        json={"scope_type": "channel", "scope_id": asset_id, "reason": "x"},
    )
    assert resp.status_code == 400
PYFILE

if pytest tests/test_rights_takedown.py -q > /logs/verifier/pytest.log 2>&1; then
  success=1.0
  success_int=1
else
  success=0.0
  success_int=0
fi

# NOTE: correct_diagnosis/policy_compliance/side_effect_safety are placeholders (fixed at 1.0),
# same as task-01/02/05/06/07 — no automated side-effect-safety check exists yet in this world.
cat > /logs/verifier/reward.json <<JSON
{
  "task_success": $success,
  "correct_diagnosis": $success,
  "policy_compliance": 1.0,
  "side_effect_safety": 1.0
}
JSON

echo "$success_int" > /logs/verifier/reward.txt
echo "verifier: task_success=$success (see pytest.log)"
