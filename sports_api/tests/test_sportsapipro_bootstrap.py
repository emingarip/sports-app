from datetime import UTC, date, datetime

import httpx

from app.core.config import Settings
from app.providers.base import BootstrapSeasonSeed, BootstrapTournamentSeed
from app.providers.sportsapipro_football_v2 import SportsAPIProFootballV2Client


async def test_bootstrap_catalog_aggregates_categories_tournaments_and_seasons(monkeypatch) -> None:
    client = SportsAPIProFootballV2Client(settings=Settings(sportsapipro_api_key="test-key"))

    payloads = {
        "/api/countries/all": {
            "data": {
                "categories": [
                    {"id": 55, "name": "England", "code": "GB"},
                    {"id": 56, "name": "Spain", "code": "ES"},
                ]
            }
        },
        "/api/categories/55/tournaments": {
            "data": {
                "groups": [
                    {
                        "uniqueTournaments": [
                            {"id": 1001, "name": "Premier League", "slug": "premier-league"}
                        ]
                    }
                ]
            }
        },
        "/api/categories/56/tournaments": {
            "data": {
                "groups": [
                    {
                        "uniqueTournaments": [
                            {"id": 2001, "name": "La Liga", "slug": "la-liga"}
                        ]
                    }
                ]
            }
        },
        "/api/tournaments": {
            "tournaments": [
                {"id": 1001, "name": "Premier League", "slug": "premier-league", "categoryId": 55},
                {"id": 2001, "name": "La Liga", "slug": "la-liga", "categoryId": 56},
            ]
        },
        "/api/tournaments/1001/seasons": {
            "seasons": [{"id": 3001, "name": "2024/2025", "isCurrent": True}]
        },
        "/api/tournaments/2001/seasons": {
            "seasons": [{"id": 4001, "name": "2024/2025", "isCurrent": True}]
        },
    }

    async def fake_get_json(path: str, *, client=None):
        return payloads[path]

    monkeypatch.setattr(client, "_get_json", fake_get_json)

    catalog = await client.bootstrap_catalog()

    assert catalog.to_stats() == {
        "categories_count": 2,
        "tournaments_count": 2,
        "seasons_count": 2,
        "errors_count": 0,
    }
    assert {category.name for category in catalog.categories} == {"England", "Spain"}
    assert {tournament.name for tournament in catalog.tournaments} == {"Premier League", "La Liga"}
    assert {season.provider_season_id for season in catalog.seasons} == {"3001", "4001"}


async def test_bootstrap_catalog_keeps_partial_results_when_a_season_request_fails(monkeypatch) -> None:
    client = SportsAPIProFootballV2Client(settings=Settings(sportsapipro_api_key="test-key"))

    async def fake_get_extended_categories(*, client=None):
        return []

    async def fake_get_all_tournaments(*, client=None):
        return [
            BootstrapTournamentSeed(
                provider_tournament_id="1001",
                name="Premier League",
                slug="premier-league",
                category_provider_id="55",
                raw={},
            ),
            BootstrapTournamentSeed(
                provider_tournament_id="2001",
                name="La Liga",
                slug="la-liga",
                category_provider_id="56",
                raw={},
            ),
        ]

    async def fake_get_tournament_seasons(tournament_id: str, *, client=None):
        if tournament_id == "2001":
            request = httpx.Request("GET", f"https://example.com/api/tournaments/{tournament_id}/seasons")
            response = httpx.Response(429, request=request)
            raise httpx.HTTPStatusError("rate limited", request=request, response=response)
        return [
            BootstrapSeasonSeed(
                provider_season_id="3001",
                tournament_provider_id=tournament_id,
                name="2024/2025",
                year=None,
                is_current=True,
                raw={},
            )
        ]

    monkeypatch.setattr(client, "get_extended_categories", fake_get_extended_categories)
    monkeypatch.setattr(client, "get_all_tournaments", fake_get_all_tournaments)
    monkeypatch.setattr(client, "get_tournament_seasons", fake_get_tournament_seasons)

    catalog = await client.bootstrap_catalog()

    assert catalog.to_stats() == {
        "categories_count": 0,
        "tournaments_count": 2,
        "seasons_count": 1,
        "errors_count": 1,
    }
    assert "Season bootstrap failed for tournament 2001" in catalog.errors[0]


async def test_fetch_matches_parses_schedule_payload(monkeypatch) -> None:
    client = SportsAPIProFootballV2Client(settings=Settings(sportsapipro_api_key="test-key"))

    async def fake_get_json(path: str, *, client=None):
        assert path == "/api/schedule/2026-04-06"
        return {
            "success": True,
            "data": {
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
            },
        }

    monkeypatch.setattr(client, "_get_json", fake_get_json)

    batch = await client.fetch(scope="matches", target_date=date(2026, 4, 6))

    assert len(batch.matches) == 1
    match = batch.matches[0]
    assert match.provider_match_id == "14025056"
    assert match.kickoff_at == datetime(2026, 4, 6, 1, 30, tzinfo=UTC)
    assert match.competition is not None
    assert match.competition.provider_tournament_id == "23"
    assert match.season is not None
    assert match.season.provider_season_id == "76457"
    assert match.home_team.provider_team_id == "2761"
    assert match.away_team.provider_team_id == "2687"
    assert match.score_home == 1
    assert match.score_away == 2
    assert match.venue_name == "Stadio Giovanni Zini"


async def test_get_match_detail_parses_event_payload(monkeypatch) -> None:
    client = SportsAPIProFootballV2Client(settings=Settings(sportsapipro_api_key="test-key"))

    async def fake_get_json(path: str, *, client=None):
        assert path == "/api/match/14025056"
        return {
            "success": True,
            "matchId": 14025056,
            "data": {
                "event": {
                    "id": 15909458,
                    "startTimestamp": 1775311200,
                    "status": {"type": "finished", "description": "Ended"},
                    "tournament": {
                        "name": "Liga 4 Mehedinți",
                        "slug": "liga-4-mehedinti",
                        "category": {
                            "name": "Romania Amateur",
                            "slug": "romania-amateur",
                            "id": 1599,
                            "country": {
                                "alpha2": "RO",
                                "alpha3": "ROU",
                                "name": "Romania",
                                "slug": "romania",
                            },
                        },
                        "uniqueTournament": {
                            "id": 19162,
                            "name": "Liga 4 Mehedinți",
                            "slug": "liga-4-mehedinti",
                            "category": {
                                "name": "Romania Amateur",
                                "slug": "romania-amateur",
                                "id": 1599,
                                "country": {
                                    "alpha2": "RO",
                                    "alpha3": "ROU",
                                    "name": "Romania",
                                    "slug": "romania",
                                },
                            },
                        },
                    },
                    "season": {"id": 82319, "name": "Liga 4 Mehedinți 25/26", "year": "25/26"},
                    "homeTeam": {
                        "id": 447175,
                        "name": "CS Pandurii Cerneți",
                        "slug": "cs-pandurii-cerneti",
                        "shortName": "Pandurii Cerneți",
                        "country": {
                            "alpha2": "RO",
                            "alpha3": "ROU",
                            "name": "Romania",
                            "slug": "romania",
                        },
                    },
                    "awayTeam": {
                        "id": 489579,
                        "name": "CS Unirea 2023 Gârla Mare",
                        "slug": "as-unirea-2023-garla-mare",
                        "shortName": "Unirea 2023 Gârla Mare",
                        "country": {
                            "alpha2": "RO",
                            "alpha3": "ROU",
                            "name": "Romania",
                            "slug": "romania",
                        },
                    },
                    "homeScore": {"current": 5},
                    "awayScore": {"current": 3},
                }
            },
        }

    monkeypatch.setattr(client, "_get_json", fake_get_json)

    match = await client.get_match_detail("14025056")

    assert match is not None
    assert match.provider_match_id == "15909458"
    assert match.kickoff_at == datetime(2026, 4, 4, 14, 0, tzinfo=UTC)
    assert match.competition is not None
    assert match.competition.provider_tournament_id == "19162"
    assert match.season is not None
    assert match.season.provider_season_id == "82319"
    assert match.home_team.provider_team_id == "447175"
    assert match.away_team.provider_team_id == "489579"
    assert match.score_home == 5
    assert match.score_away == 3


async def test_get_team_players_parses_roster_payload(monkeypatch) -> None:
    client = SportsAPIProFootballV2Client(settings=Settings(sportsapipro_api_key="test-key"))

    async def fake_get_json(path: str, *, client=None):
        assert path == "/api/teams/42/players"
        return {
            "success": True,
            "data": {
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
            },
        }

    monkeypatch.setattr(client, "_get_json", fake_get_json)

    players = await client.get_team_players("42")

    assert len(players) == 1
    player = players[0]
    assert player.provider_player_id == "804508"
    assert player.full_name == "Viktor Gyokeres"
    assert player.short_name == "V. Gyokeres"
    assert player.slug == "viktor-gyokeres"
    assert player.team_provider_id == "42"
    assert player.squad_number == 14
    assert player.role == "ST"
    assert player.date_of_birth == date(1998, 6, 4)
    assert player.country is not None
    assert player.country.slug == "sweden"


async def test_get_match_lineup_parses_lineup_payload(monkeypatch) -> None:
    client = SportsAPIProFootballV2Client(settings=Settings(sportsapipro_api_key="test-key"))

    async def fake_get_json(path: str, *, client=None):
        assert path == "/api/match/14025056/lineups"
        return {
            "success": True,
            "matchId": 14025056,
            "data": {
                "confirmed": True,
                "home": {
                    "formation": "4-3-3",
                    "players": [
                        {
                            "teamId": 1,
                            "shirtNumber": 14,
                            "position": "F",
                            "substitute": False,
                            "played": True,
                            "minutesPlayed": 90,
                            "statistics": {"rating": 7.4},
                            "player": {
                                "id": 804508,
                                "name": "Viktor Gyokeres",
                                "slug": "viktor-gyokeres",
                                "shortName": "V. Gyokeres",
                                "dateOfBirth": "1998-06-04T00:00:00+00:00",
                                "country": {
                                    "alpha2": "SE",
                                    "alpha3": "SWE",
                                    "name": "Sweden",
                                    "slug": "sweden",
                                },
                            },
                        }
                    ],
                },
                "away": {
                    "formation": "4-4-2",
                    "players": [
                        {
                            "teamId": 2,
                            "jerseyNumber": 9,
                            "position": "F",
                            "substitute": True,
                            "played": False,
                            "minutesPlayed": 0,
                            "player": {
                                "id": 9001,
                                "name": "Away Striker",
                                "slug": "away-striker",
                            },
                        }
                    ],
                },
            },
        }

    monkeypatch.setattr(client, "_get_json", fake_get_json)

    lineup = await client.get_match_lineup("14025056")

    assert lineup is not None
    assert lineup.provider_match_id == "14025056"
    assert lineup.confirmed is True
    assert lineup.home_formation == "4-3-3"
    assert lineup.away_formation == "4-4-2"
    assert len(lineup.home_players) == 1
    assert len(lineup.away_players) == 1
    home_entry = lineup.home_players[0]
    away_entry = lineup.away_players[0]
    assert home_entry.team_side == "home"
    assert home_entry.is_starter is True
    assert home_entry.played is True
    assert home_entry.minutes_played == 90
    assert home_entry.statistics == {"rating": 7.4}
    assert home_entry.player.provider_player_id == "804508"
    assert home_entry.player.team_provider_id == "1"
    assert home_entry.player.squad_number == 14
    assert away_entry.team_side == "away"
    assert away_entry.is_substitute is True
    assert away_entry.played is False
    assert away_entry.player.provider_player_id == "9001"
    assert away_entry.player.team_provider_id == "2"
    assert away_entry.player.squad_number == 9
