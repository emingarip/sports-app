from datetime import UTC, date, datetime
from uuid import uuid4

from fastapi.testclient import TestClient

from app.api.deps import get_db_session
from app.main import app


def test_catalog_overview_route_returns_counts(monkeypatch) -> None:
    async def override_session():
        yield object()

    async def fake_build_catalog_overview(_session):
        return {"counts": {"countries": 12, "competitions": 34}}

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr("app.api.routes.catalog.build_catalog_overview", fake_build_catalog_overview)

    client = TestClient(app)
    response = client.get("/api/v1/catalog/overview")

    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()["counts"]["countries"] == 12


def test_countries_route_forwards_filters(monkeypatch) -> None:
    async def override_session():
        yield object()

    async def fake_list_countries(*, session, q, limit):
        assert q == "eng"
        assert limit == 20
        return [
            {
                "id": str(uuid4()),
                "entity_uid": "country:england",
                "name": "England",
                "slug": "england",
                "iso_code2": "GB",
                "iso_code3": None,
            }
        ]

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr("app.api.routes.catalog.list_countries", fake_list_countries)

    client = TestClient(app)
    response = client.get("/api/v1/countries?q=eng&limit=20")

    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()[0]["slug"] == "england"


def test_competitions_route_returns_nested_country(monkeypatch) -> None:
    async def override_session():
        yield object()

    async def fake_list_competitions(*, session, q, country_slug, limit):
        assert country_slug == "england"
        return [
            {
                "id": str(uuid4()),
                "entity_uid": "competition:england:premier-league",
                "name": "Premier League",
                "slug": "england-premier-league",
                "competition_type": "league",
                "country": {
                    "id": str(uuid4()),
                    "entity_uid": "country:england",
                    "name": "England",
                    "slug": "england",
                },
            }
        ]

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr("app.api.routes.catalog.list_competitions", fake_list_competitions)

    client = TestClient(app)
    response = client.get("/api/v1/competitions?country_slug=england")

    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()[0]["country"]["slug"] == "england"


def test_seasons_route_forwards_competition_slug(monkeypatch) -> None:
    async def override_session():
        yield object()

    async def fake_list_seasons(*, session, competition_slug, current_only, limit):
        assert competition_slug == "england-premier-league"
        assert current_only is True
        return [
            {
                "id": str(uuid4()),
                "entity_uid": "season:2025-2026",
                "label": "2025/2026",
                "start_date": date(2025, 8, 1),
                "end_date": date(2026, 5, 31),
                "is_current": True,
            }
        ]

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr("app.api.routes.catalog.list_seasons", fake_list_seasons)

    client = TestClient(app)
    response = client.get("/api/v1/seasons?competition_slug=england-premier-league&current_only=true")

    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()[0]["is_current"] is True


def test_sync_runs_route_returns_provider(monkeypatch) -> None:
    async def override_session():
        yield object()

    async def fake_list_sync_runs(*, session, scope, provider_slug, limit):
        assert scope == "bootstrap-countries"
        assert provider_slug == "sportsapipro-football-v2"
        assert limit == 5
        return [
            {
                "id": str(uuid4()),
                "scope": "bootstrap-countries",
                "status": "succeeded",
                "target_date": None,
                "stats": {"categories_count": 12},
                "error_message": None,
                "started_at": datetime(2026, 4, 5, 12, 0, tzinfo=UTC),
                "completed_at": datetime(2026, 4, 5, 12, 1, tzinfo=UTC),
                "provider": {
                    "id": str(uuid4()),
                    "slug": "sportsapipro-football-v2",
                    "name": "SportsAPI Pro Football V2",
                },
            }
        ]

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr("app.api.routes.catalog.list_sync_runs", fake_list_sync_runs)

    client = TestClient(app)
    response = client.get(
        "/api/v1/sync-runs?scope=bootstrap-countries&provider_slug=sportsapipro-football-v2&limit=5"
    )

    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()[0]["provider"]["slug"] == "sportsapipro-football-v2"


def test_matches_route_forwards_timezone(monkeypatch) -> None:
    async def override_session():
        yield object()

    async def fake_list_matches(*, session, target_date, limit, timezone_name):
        assert target_date == date(2026, 4, 6)
        assert limit == 20
        assert timezone_name == "Europe/Istanbul"
        return [
            {
                "id": str(uuid4()),
                "entity_uid": "match:1",
                "kickoff_at": datetime(2026, 4, 6, 21, 0, tzinfo=UTC),
                "status": "scheduled",
                "home_team": {
                    "id": str(uuid4()),
                    "entity_uid": "team:home",
                    "name": "Home FC",
                    "short_name": "HOME",
                },
                "away_team": {
                    "id": str(uuid4()),
                    "entity_uid": "team:away",
                    "name": "Away FC",
                    "short_name": "AWAY",
                },
                "competition": None,
                "season": None,
                "score_home": None,
                "score_away": None,
            }
        ]

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr("app.api.routes.matches.list_matches", fake_list_matches)

    client = TestClient(app)
    response = client.get("/api/v1/matches?date=2026-04-06&tz=Europe/Istanbul&limit=20")

    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()[0]["entity_uid"] == "match:1"
