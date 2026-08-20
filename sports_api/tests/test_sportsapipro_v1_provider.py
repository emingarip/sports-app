from datetime import UTC, datetime

from app.core.config import Settings
from app.providers.sportsapipro_football_v1 import SportsAPIProFootballV1Client


async def test_get_prematch_markets_falls_back_to_game_best_odds(monkeypatch) -> None:
    client = SportsAPIProFootballV1Client(settings=Settings(sportsapipro_api_key="test-key"))
    client._matchup_id_cache["4001"] = "1-2-3"

    async def fake_get_json(path: str, *, params=None, client=None):
        if path == "/bets/lines":
            return {"lines": []}
        if path == "/game":
            return {
                "game": {
                    "startTime": "2026-04-07T18:00:00+00:00",
                    "bestOdds": [
                        {
                            "lineId": 1,
                            "lineType": {"name": "Full Time Result", "shortName": "1X2"},
                            "options": [
                                {"num": 1, "name": "1", "rate": {"decimal": 2.2}, "originalRate": {"decimal": 2.4}},
                                {"num": 2, "name": "X", "rate": {"decimal": 3.1}, "originalRate": {"decimal": 3.0}},
                                {"num": 3, "name": "2", "rate": {"decimal": 3.4}, "originalRate": {"decimal": 3.2}},
                            ],
                        },
                        {
                            "lineId": 2,
                            "lineType": {"name": "Total Goals In Match", "shortName": "O/U"},
                            "internalOptionValue": "2.5",
                            "options": [
                                {"num": 1, "name": "Under", "rate": {"decimal": 1.8}, "originalRate": {"decimal": 1.9}},
                                {"num": 2, "name": "Over", "rate": {"decimal": 1.9}, "originalRate": {"decimal": 1.95}},
                            ],
                        },
                    ]
                }
            }
        raise AssertionError(path)

    monkeypatch.setattr(client, "_get_json", fake_get_json)

    ticks = await client.get_prematch_markets("4001")

    indexed = {(tick.market_type, tick.selection_key): tick for tick in ticks}
    assert indexed[("1x2", "home")].odds_decimal == 2.4
    assert indexed[("1x2", "draw")].odds_decimal == 3.0
    assert indexed[("1x2", "away")].odds_decimal == 3.2
    assert indexed[("totals", "under")].line_value == 2.5
    assert indexed[("totals", "over")].odds_decimal == 1.95


async def test_get_live_markets_falls_back_to_game_best_odds_and_maps_next_goal(monkeypatch) -> None:
    client = SportsAPIProFootballV1Client(settings=Settings(sportsapipro_api_key="test-key"))
    client._matchup_id_cache["4002"] = "1-2-3"

    async def fake_get_json(path: str, *, params=None, client=None):
        if path == "/bets/lines":
            return {"lines": []}
        if path == "/game":
            return {
                "game": {
                    "startTime": "2026-04-07T18:00:00+00:00",
                    "gameTime": 67,
                    "bestOdds": [
                        {
                            "lineId": 7,
                            "lineType": {"name": "First To Score"},
                            "options": [
                                {"num": 1, "name": "Home", "rate": {"decimal": 1.7}},
                                {"num": 2, "name": "No Goal", "rate": {"decimal": 5.5}},
                                {"num": 3, "name": "Away", "rate": {"decimal": 2.8}},
                            ],
                        }
                    ],
                }
            }
        raise AssertionError(path)

    monkeypatch.setattr(client, "_get_json", fake_get_json)

    ticks = await client.get_live_markets("4002")

    indexed = {(tick.market_type, tick.selection_key): tick for tick in ticks}
    assert indexed[("next_goal", "home")].minute == 67
    assert indexed[("next_goal", "home")].tick_time == datetime(2026, 4, 7, 19, 7, tzinfo=UTC)
    assert indexed[("next_goal", "no_goal")].odds_decimal == 5.5
    assert indexed[("next_goal", "away")].odds_decimal == 2.8


async def test_get_prematch_markets_skips_game_fallback_when_matchup_cache_is_missing(
    monkeypatch,
) -> None:
    client = SportsAPIProFootballV1Client(settings=Settings(sportsapipro_api_key="test-key"))

    async def fake_get_json(path: str, *, params=None, client=None):
        if path == "/bets/lines":
            return {"lines": []}
        raise AssertionError(path)

    monkeypatch.setattr(client, "_get_json", fake_get_json)

    ticks = await client.get_prematch_markets("4999")

    assert ticks == []
