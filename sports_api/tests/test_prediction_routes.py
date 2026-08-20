import uuid
from datetime import UTC, datetime

from fastapi.testclient import TestClient

from app.api.deps import get_db_session
from app.db.models.domain import SnapshotPhase
from app.main import app
from app.schemas.bulletin import (
    BulletinMarketOdds,
    BulletinSelectionOdds,
    MatchOddsResponse,
)
from app.services.bulletin_service import TickRow
from app.services.prediction_service import _offered_odds_from_ticks


class FakePrediction:
    def __init__(self, match_id) -> None:
        self.match_id = match_id
        self.model_version = "dc-v1"
        self.phase = SnapshotPhase.pre
        self.generated_at = datetime(2026, 7, 11, 8, 0, tzinfo=UTC)
        self.lambda_home = 1.62
        self.lambda_away = 1.05
        self.rho = -0.04
        self.market_probs = {
            "MS": {"home": 0.52, "draw": 0.26, "away": 0.22},
            "AU_2_5": {"over": 0.55, "under": 0.45},
        }
        self.value_picks = [
            {
                "market_code": "MS",
                "selection_key": "home",
                "model_probability": 0.52,
                "odds_decimal": 2.30,
                "implied_probability": 0.4348,
                "expected_value": 0.196,
                "kelly_stake": 0.0377,
            }
        ]
        self.metadata_json = {"trained_matches": 420}


def test_match_prediction_route_builds_comparisons(monkeypatch) -> None:
    match_id = uuid.uuid4()

    class FakePredictionService:
        def __init__(self, _session) -> None:
            pass

        async def get_prediction(self, *, match_id):
            return FakePrediction(match_id)

    class FakeBulletinService:
        def __init__(self, _session) -> None:
            pass

        async def get_match_odds(self, *, match_id):
            return MatchOddsResponse(
                match_id=str(match_id),
                home_team="Ev",
                away_team="Deplasman",
                kickoff_at=datetime(2026, 7, 12, 18, 45, tzinfo=UTC),
                markets=[
                    BulletinMarketOdds(
                        market_code="MS",
                        market_type="1x2",
                        name_tr="Maç Sonucu",
                        selections=[
                            BulletinSelectionOdds(selection_key="home", odds=2.30),
                            BulletinSelectionOdds(selection_key="draw", odds=3.40),
                            BulletinSelectionOdds(selection_key="away", odds=3.10),
                        ],
                    )
                ],
                history=[],
            )

    async def override_session():
        yield object()

    monkeypatch.setattr("app.api.routes.predictions.PredictionService", FakePredictionService)
    monkeypatch.setattr("app.api.routes.predictions.BulletinService", FakeBulletinService)
    app.dependency_overrides[get_db_session] = override_session
    client = TestClient(app)
    response = client.get(f"/api/v1/matches/{match_id}/prediction")
    app.dependency_overrides.clear()

    assert response.status_code == 200
    body = response.json()
    assert body["model_version"] == "dc-v1"
    assert body["trained_matches"] == 420
    assert body["market_probs"]["MS"]["home"] == 0.52

    ms_comparison = next(item for item in body["comparisons"] if item["market_code"] == "MS")
    home = next(sel for sel in ms_comparison["selections"] if sel["selection_key"] == "home")
    assert home["odds"] == 2.30
    assert home["expected_value"] > 0.15
    assert home["is_value"] is True
    # Draw offered at 3.40 with model prob 0.26 -> EV < threshold.
    draw = next(sel for sel in ms_comparison["selections"] if sel["selection_key"] == "draw")
    assert draw["is_value"] is False

    # AU_2_5 has no offered odds: comparison exists with odds null.
    au = next(item for item in body["comparisons"] if item["market_code"] == "AU_2_5")
    over = next(sel for sel in au["selections"] if sel["selection_key"] == "over")
    assert over["odds"] is None
    assert over["is_value"] is False


def test_match_prediction_route_404_when_missing(monkeypatch) -> None:
    class FakePredictionService:
        def __init__(self, _session) -> None:
            pass

        async def get_prediction(self, *, match_id):
            return None

    async def override_session():
        yield object()

    monkeypatch.setattr("app.api.routes.predictions.PredictionService", FakePredictionService)
    app.dependency_overrides[get_db_session] = override_session
    client = TestClient(app)
    response = client.get(f"/api/v1/matches/{uuid.uuid4()}/prediction")
    app.dependency_overrides.clear()

    assert response.status_code == 404


def test_offered_odds_from_ticks_uses_latest_unsuspended() -> None:
    t0 = datetime(2026, 7, 10, 9, 0, tzinfo=UTC)
    ticks = [
        TickRow(
            market_type="1x2",
            selection_key="home",
            line_value=None,
            odds_decimal=2.5,
            implied_prob=0.4,
            normalized_prob=None,
            tick_time=t0,
        ),
        TickRow(
            market_type="totals",
            selection_key="over",
            line_value=2.5,
            odds_decimal=1.8,
            implied_prob=1 / 1.8,
            normalized_prob=None,
            tick_time=t0,
        ),
    ]
    offered = _offered_odds_from_ticks(ticks)
    assert offered["MS"]["home"] == 2.5
    assert offered["AU_2_5"]["over"] == 1.8
