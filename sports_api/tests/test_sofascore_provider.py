from datetime import UTC, date, datetime

import pytest

from app.core.config import Settings
from app.providers.registry import REGISTERED_PROVIDER_CLIENTS
from app.providers.sofascore_football import SofascoreFootballClient, SofascoreRequestError


async def test_sofascore_fetch_matches_parses_scheduled_events(monkeypatch) -> None:
    client = SofascoreFootballClient(settings=Settings())

    async def fake_get_json_via_browser(path: str):
        assert path == "/api/v1/sport/football/scheduled-events/2026-04-06"
        return {
            "events": [
                {
                    "id": 14025056,
                    "startTimestamp": 1775439000,
                    "status": {"type": "finished", "description": "Ended"},
                    "tournament": {
                        "name": "Serie A",
                        "slug": "serie-a",
                        "category": {
                            "name": "Italy",
                            "slug": "italy",
                            "id": 31,
                            "sport": {"id": 1, "name": "Football", "slug": "football"},
                            "country": {
                                "alpha2": "IT",
                                "alpha3": "ITA",
                                "name": "Italy",
                                "slug": "italy",
                            },
                        },
                        "uniqueTournament": {
                            "id": 23,
                            "name": "Serie A",
                            "slug": "serie-a",
                            "category": {
                                "name": "Italy",
                                "slug": "italy",
                                "id": 31,
                                "sport": {"id": 1, "name": "Football", "slug": "football"},
                                "country": {
                                    "alpha2": "IT",
                                    "alpha3": "ITA",
                                    "name": "Italy",
                                    "slug": "italy",
                                },
                            },
                        },
                    },
                    "season": {"id": 76457, "name": "Serie A 25/26", "year": "25/26"},
                    "homeTeam": {
                        "id": 2761,
                        "name": "Cremonese",
                        "slug": "cremonese",
                        "shortName": "Cremonese",
                        "sport": {"id": 1, "name": "Football", "slug": "football"},
                        "country": {
                            "alpha2": "IT",
                            "alpha3": "ITA",
                            "name": "Italy",
                            "slug": "italy",
                        },
                    },
                    "awayTeam": {
                        "id": 2687,
                        "name": "Bologna",
                        "slug": "bologna",
                        "shortName": "Bologna",
                        "sport": {"id": 1, "name": "Football", "slug": "football"},
                        "country": {
                            "alpha2": "IT",
                            "alpha3": "ITA",
                            "name": "Italy",
                            "slug": "italy",
                        },
                    },
                    "homeScore": {"current": 1},
                    "awayScore": {"current": 2},
                    "venue": {"name": "Stadio Giovanni Zini"},
                }
            ]
        }

    monkeypatch.setattr(client, "_get_json_via_browser", fake_get_json_via_browser)

    batch = await client.fetch(scope="matches", target_date=date(2026, 4, 6))

    assert len(batch.matches) == 1
    match = batch.matches[0]
    assert match.provider_match_id == "14025056"
    assert match.kickoff_at == datetime(2026, 4, 6, 1, 30, tzinfo=UTC)
    assert match.competition is not None
    assert match.competition.provider_tournament_id == "23"
    assert match.home_team.provider_team_id == "2761"
    assert match.away_team.provider_team_id == "2687"
    assert match.score_home == 1
    assert match.score_away == 2


async def test_sofascore_team_players_parse_roster(monkeypatch) -> None:
    client = SofascoreFootballClient(settings=Settings())

    async def fake_get_json_via_browser(path: str):
        assert path == "/api/v1/team/42/players"
        return {
            "players": [
                {
                    "player": {
                        "id": 804508,
                        "name": "Viktor Gyokeres",
                        "slug": "viktor-gyokeres",
                        "shortName": "V. Gyokeres",
                        "position": "F",
                        "positionsDetailed": ["ST"],
                        "shirtNumber": 14,
                        "dateOfBirth": "1998-06-04T00:00:00+00:00",
                        "country": {
                            "alpha2": "SE",
                            "alpha3": "SWE",
                            "name": "Sweden",
                            "slug": "sweden",
                        },
                    }
                }
            ]
        }

    monkeypatch.setattr(client, "_get_json_via_browser", fake_get_json_via_browser)

    players = await client.get_team_players("42")

    assert len(players) == 1
    player = players[0]
    assert player.provider_player_id == "804508"
    assert player.full_name == "Viktor Gyokeres"
    assert player.slug == "viktor-gyokeres"
    assert player.team_provider_id == "42"
    assert player.squad_number == 14
    assert player.role == "ST"
    assert player.date_of_birth == date(1998, 6, 4)
    assert player.country is not None
    assert player.country.slug == "sweden"


async def test_sofascore_match_lineup_parses_players(monkeypatch) -> None:
    client = SofascoreFootballClient(settings=Settings())

    async def fake_get_json_via_browser(path: str, *, allow_not_found: bool = False):
        assert path == "/api/v1/event/13981725/lineups"
        assert allow_not_found is True
        return {
            "eventId": 13981725,
            "confirmed": True,
            "home": {
                "formation": "4-2-3-1",
                "team": {"id": 2761},
                "players": [
                    {
                        "player": {
                            "id": 804508,
                            "name": "Viktor Gyokeres",
                            "slug": "viktor-gyokeres",
                            "shortName": "V. Gyokeres",
                            "country": {
                                "alpha2": "SE",
                                "alpha3": "SWE",
                                "name": "Sweden",
                                "slug": "sweden",
                            },
                        },
                        "position": "F",
                        "shirtNumber": 14,
                        "substitute": False,
                        "statistics": {"minutesPlayed": "90", "goals": 1},
                    }
                ],
            },
            "away": {
                "formation": "3-4-3",
                "teamId": 2687,
                "players": [
                    {
                        "player": {
                            "id": 901122,
                            "name": "Lewis Ferguson",
                            "slug": "lewis-ferguson",
                            "shortName": "L. Ferguson",
                            "country": {
                                "alpha2": "GB",
                                "alpha3": "GBR",
                                "name": "Scotland",
                                "slug": "scotland",
                            },
                        },
                        "position": "M",
                        "shirtNumber": 19,
                        "substitute": True,
                        "played": False,
                    }
                ],
            },
        }

    monkeypatch.setattr(client, "_get_json_via_browser", fake_get_json_via_browser)

    lineup = await client.get_match_lineup("13981725")

    assert lineup is not None
    assert lineup.provider_match_id == "13981725"
    assert lineup.confirmed is True
    assert lineup.home_formation == "4-2-3-1"
    assert lineup.away_formation == "3-4-3"
    assert len(lineup.home_players) == 1
    assert len(lineup.away_players) == 1
    assert lineup.home_players[0].player.provider_player_id == "804508"
    assert lineup.home_players[0].played is True
    assert lineup.home_players[0].minutes_played == 90
    assert lineup.home_players[0].is_starter is True
    assert lineup.home_players[0].is_substitute is False
    assert lineup.home_players[0].player.team_provider_id == "2761"
    assert lineup.away_players[0].player.provider_player_id == "901122"
    assert lineup.away_players[0].played is False
    assert lineup.away_players[0].is_starter is False
    assert lineup.away_players[0].is_substitute is True
    assert lineup.away_players[0].player.team_provider_id == "2687"


async def test_sofascore_match_lineup_returns_none_when_endpoint_missing(monkeypatch) -> None:
    client = SofascoreFootballClient(settings=Settings())

    async def fake_get_json_via_browser(path: str, *, allow_not_found: bool = False):
        assert path == "/api/v1/event/15898306/lineups"
        assert allow_not_found is True
        return None

    monkeypatch.setattr(client, "_get_json_via_browser", fake_get_json_via_browser)

    lineup = await client.get_match_lineup("15898306")

    assert lineup is None


async def test_sofascore_match_lineup_marks_players_with_zeroed_stats_as_played(
    monkeypatch,
) -> None:
    client = SofascoreFootballClient(settings=Settings())

    async def fake_get_json_via_browser(path: str, *, allow_not_found: bool = False):
        assert path == "/api/v1/event/15820475/lineups"
        assert allow_not_found is True
        return {
            "eventId": 15820475,
            "confirmed": True,
            "home": {
                "team": {"id": 4021},
                "players": [
                    {
                        "player": {
                            "id": 1001,
                            "name": "Starter With Zero Stats",
                            "slug": "starter-with-zero-stats",
                        },
                        "position": "D",
                        "shirtNumber": 3,
                        "substitute": False,
                        "statistics": {
                            "goals": 0,
                            "ownGoals": 0,
                            "totalShots": 0,
                            "statisticsType": "summary",
                        },
                    },
                    {
                        "player": {
                            "id": 1002,
                            "name": "Unused Bench Player",
                            "slug": "unused-bench-player",
                        },
                        "position": "M",
                        "shirtNumber": 18,
                        "substitute": True,
                    },
                ],
            },
            "away": {
                "team": {"id": 4022},
                "players": [
                    {
                        "player": {
                            "id": 2001,
                            "name": "Substitute With Zero Stats",
                            "slug": "substitute-with-zero-stats",
                        },
                        "position": "F",
                        "shirtNumber": 17,
                        "substitute": True,
                        "statistics": {
                            "goals": 0,
                            "ownGoals": 0,
                            "totalShots": 0,
                            "statisticsType": "summary",
                        },
                    }
                ],
            },
        }

    monkeypatch.setattr(client, "_get_json_via_browser", fake_get_json_via_browser)

    lineup = await client.get_match_lineup("15820475")

    assert lineup is not None
    assert lineup.home_players[0].played is True
    assert lineup.home_players[1].played is False
    assert lineup.away_players[0].played is True


async def test_sofascore_provider_uses_threaded_browser_fetch_on_windows(monkeypatch) -> None:
    client = SofascoreFootballClient(settings=Settings())
    calls: list[str] = []

    async def fake_run_sync_browser_call(func, path: str):
        calls.append(path)
        assert func == client._sync_fetch_json_via_browser_once
        return {"status": 200, "text": '{"events": []}'}

    monkeypatch.setattr(client, "_use_threaded_playwright", lambda: True)
    monkeypatch.setattr(client, "_run_sync_browser_call", fake_run_sync_browser_call)

    payload = await client._get_json_via_browser("/api/v1/sport/football/scheduled-events/2026-04-06")

    assert payload == {"events": []}
    assert calls == ["/api/v1/sport/football/scheduled-events/2026-04-06"]


def test_sofascore_provider_is_registered() -> None:
    assert REGISTERED_PROVIDER_CLIENTS["sofascore-football"] is SofascoreFootballClient


def test_sofascore_schedule_path_uses_date_page_referrer() -> None:
    client = SofascoreFootballClient(settings=Settings())

    assert (
        client._page_url_for_path("/api/v1/sport/football/scheduled-events/2026-04-04")
        == "https://www.sofascore.com/football/2026-04-04"
    )
    assert client._page_url_for_path("/api/v1/team/42/players") == "https://www.sofascore.com/"


async def test_sofascore_provider_retries_429_and_reuses_session(monkeypatch) -> None:
    client = SofascoreFootballClient(settings=Settings())
    sleeps: list[float] = []
    reset_calls: list[str] = []
    responses = [
        {"status": 429, "text": "{}"},
        {"status": 200, "text": '{"events": []}'},
    ]

    async def fake_fetch_once(path: str):
        assert path == "/api/v1/sport/football/scheduled-events/2026-04-06"
        return responses.pop(0)

    async def fake_reset() -> None:
        reset_calls.append("reset")

    async def fake_sleep(delay: float) -> None:
        sleeps.append(delay)

    monkeypatch.setattr(client, "_fetch_json_via_browser_once", fake_fetch_once)
    monkeypatch.setattr(client, "_reset_browser_session", fake_reset)
    monkeypatch.setattr(client, "_sleep", fake_sleep)
    monkeypatch.setattr(client, "_random_uniform", lambda start, end: 0.0)

    payload = await client._get_json_via_browser("/api/v1/sport/football/scheduled-events/2026-04-06")

    assert payload == {"events": []}
    assert reset_calls == ["reset"]
    assert sleeps == [client.settings.sofascore_retry_backoff_seconds]


async def test_sofascore_provider_raises_403_after_retries(monkeypatch) -> None:
    client = SofascoreFootballClient(
        settings=Settings(
            sofascore_max_retries=2,
            sofascore_forbidden_backoff_seconds=12.0,
        )
    )
    sleeps: list[float] = []

    async def fake_fetch_once(path: str):
        return {"status": 403, "text": "blocked"}

    async def fake_reset() -> None:
        return None

    async def fake_sleep(delay: float) -> None:
        sleeps.append(delay)

    monkeypatch.setattr(client, "_fetch_json_via_browser_once", fake_fetch_once)
    monkeypatch.setattr(client, "_reset_browser_session", fake_reset)
    monkeypatch.setattr(client, "_sleep", fake_sleep)
    monkeypatch.setattr(client, "_random_uniform", lambda start, end: 0.0)

    with pytest.raises(SofascoreRequestError) as exc_info:
        await client._get_json_via_browser("/api/v1/sport/football/scheduled-events/2026-04-06")

    assert exc_info.value.status_code == 403
    assert sleeps == [12.0]


async def test_sofascore_provider_returns_none_for_404_when_allowed(monkeypatch) -> None:
    client = SofascoreFootballClient(settings=Settings())

    async def fake_fetch_once(path: str):
        assert path == "/api/v1/event/15898306/lineups"
        return {"status": 404, "text": '{"error":{"code":404,"message":"Not Found"}}'}

    monkeypatch.setattr(client, "_fetch_json_via_browser_once", fake_fetch_once)

    payload = await client._get_json_via_browser(
        "/api/v1/event/15898306/lineups",
        allow_not_found=True,
    )

    assert payload is None
