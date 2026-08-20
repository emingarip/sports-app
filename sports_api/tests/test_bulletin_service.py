from datetime import UTC, date, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from app.api.deps import get_db_session
from app.main import app
from app.schemas.bulletin import BulletinResponse
from app.services.bulletin_service import (
    TickRow,
    build_market_views,
    build_selection_histories,
)

T0 = datetime(2026, 7, 10, 9, 0, tzinfo=UTC)


def tick(
    market_type: str,
    selection_key: str,
    odds: float,
    *,
    line: float | None = None,
    at: datetime = T0,
    suspended: bool = False,
) -> TickRow:
    return TickRow(
        market_type=market_type,
        selection_key=selection_key,
        line_value=line,
        odds_decimal=odds,
        implied_prob=1.0 / odds,
        normalized_prob=None,
        tick_time=at,
        suspended=suspended,
    )


def test_build_market_views_computes_opening_and_movement() -> None:
    later = T0 + timedelta(hours=6)
    views = build_market_views(
        [
            tick("1x2", "home", 2.50, at=T0),
            tick("1x2", "home", 2.20, at=later),
            tick("1x2", "draw", 3.30, at=T0),
            tick("1x2", "away", 2.90, at=T0),
            tick("totals", "over", 1.80, line=2.5, at=T0),
        ]
    )

    assert [view.market_code for view in views] == ["MS", "AU_2_5"]
    ms = views[0]
    assert ms.name_tr == "Maç Sonucu"
    home = ms.selections[0]
    assert home.selection_key == "home"
    assert home.label_tr == "1"
    assert home.odds == pytest.approx(2.20)
    assert home.opening_odds == pytest.approx(2.50)
    assert home.movement_pct == pytest.approx(-12.0)
    assert home.is_dropping is True

    draw = ms.selections[1]
    assert draw.movement_pct is None
    assert draw.is_dropping is False
    assert ms.last_tick_at == later


def test_build_market_views_drops_unmapped_markets_and_lines() -> None:
    views = build_market_views(
        [
            tick("corners", "over", 1.90),
            tick("totals", "over", 1.90, line=7.5),
            tick("1x2", "home", 0.95),  # nonsense odds
        ]
    )
    assert views == []


def test_build_market_views_respects_market_code_filter() -> None:
    views = build_market_views(
        [
            tick("1x2", "home", 2.0),
            tick("btts", "yes", 1.7),
        ],
        market_codes={"KG"},
    )
    assert [view.market_code for view in views] == ["KG"]


def test_build_selection_histories_orders_points() -> None:
    later = T0 + timedelta(hours=2)
    histories = build_selection_histories(
        [
            tick("1x2", "home", 2.2, at=later),
            tick("1x2", "home", 2.5, at=T0),
            tick("1x2", "draw", 3.3, at=T0),
        ]
    )
    assert len(histories) == 2
    home = histories[0]
    assert home.selection_key == "home"
    assert [point.odds for point in home.points] == [2.5, 2.2]


def test_bulletin_route_validates_market_codes(monkeypatch) -> None:
    async def override_session():
        yield object()

    app.dependency_overrides[get_db_session] = override_session
    client = TestClient(app)
    response = client.get("/api/v1/bulletin?markets=MS,NOPE")
    app.dependency_overrides.clear()

    assert response.status_code == 422
    assert "NOPE" in response.json()["detail"]


def test_bulletin_route_returns_payload(monkeypatch) -> None:
    async def override_session():
        yield object()

    class FakeBulletinService:
        def __init__(self, _session) -> None:
            pass

        async def get_bulletin(self, **kwargs):
            assert kwargs["market_codes"] == {"MS"}
            return BulletinResponse(
                target_date=date(2026, 7, 12),
                timezone="Europe/Istanbul",
                match_count=0,
                matches=[],
            )

    monkeypatch.setattr("app.api.routes.bulletin.BulletinService", FakeBulletinService)
    app.dependency_overrides[get_db_session] = override_session
    client = TestClient(app)
    response = client.get("/api/v1/bulletin?date=2026-07-12&markets=ms")
    app.dependency_overrides.clear()

    assert response.status_code == 200
    body = response.json()
    assert body["match_count"] == 0
    assert body["timezone"] == "Europe/Istanbul"
