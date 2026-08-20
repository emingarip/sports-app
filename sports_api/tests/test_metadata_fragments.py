from datetime import UTC, datetime

from app.providers.base import BootstrapSeasonSeed, ProviderMatchSeed, ProviderPlayerSeed, ProviderTeamSeed
from app.services.bootstrap_persistence import BootstrapPersistenceService
from app.services.match_persistence import MatchPersistenceService
from app.services.player_persistence import PlayerPersistenceService


def test_season_metadata_fragment_exposes_normalized_label_and_year() -> None:
    seed = BootstrapSeasonSeed(
        provider_season_id="500",
        tournament_provider_id="100",
        name="2026",
        year="2026",
        is_current=True,
    )

    assert BootstrapPersistenceService._season_metadata_fragment(
        seed=seed,
        normalized_label="25/26",
    ) == {
        "provider_year": "2026",
        "normalized_label": "25/26",
    }


def test_match_metadata_fragment_exposes_round_and_venue_details() -> None:
    seed = ProviderMatchSeed(
        provider_match_id="14025056",
        kickoff_at=datetime(2026, 4, 6, 1, 30, tzinfo=UTC),
        status="finished",
        provider_status="Ended",
        home_team=ProviderTeamSeed(provider_team_id="1", name="Home FC"),
        away_team=ProviderTeamSeed(provider_team_id="2", name="Away FC"),
        venue_name="Stadio Giovanni Zini",
        raw={
            "startTimestamp": 1775439000,
            "winnerCode": 2,
            "status": {"type": "finished", "description": "Ended"},
            "roundInfo": {"round": 31},
            "venue": {"name": "Stadio Giovanni Zini", "city": {"name": "Cremona"}},
        },
    )

    assert MatchPersistenceService._match_metadata_fragment(seed) == {
        "provider_start_timestamp": 1775439000,
        "provider_winner_code": 2,
        "provider_status_type": "finished",
        "provider_status_description": "Ended",
        "provider_round_info": {"round": 31},
        "provider_venue": {"name": "Stadio Giovanni Zini", "city": {"name": "Cremona"}},
    }


def test_team_metadata_fragment_exposes_name_code_and_colors() -> None:
    seed = ProviderTeamSeed(
        provider_team_id="2761",
        name="Cremonese",
        raw={
            "nameCode": "CRE",
            "teamColors": {"primary": "#c00", "secondary": "#999", "text": "#fff"},
        },
    )

    assert MatchPersistenceService._team_metadata_fragment(seed) == {
        "provider_name_code": "CRE",
        "provider_team_colors": {"primary": "#c00", "secondary": "#999", "text": "#fff"},
    }


def test_player_metadata_fragment_exposes_position_and_profile_details() -> None:
    seed = ProviderPlayerSeed(
        provider_player_id="804508",
        full_name="Viktor Gyokeres",
        team_provider_id="42",
        squad_number=14,
        role="ST",
        is_current=True,
        raw={
            "player": {
                "position": "F",
                "positionsDetailed": ["ST"],
                "preferredFoot": "right",
                "height": 187,
                "weight": 84,
            }
        },
    )

    assert PlayerPersistenceService._player_metadata_fragment(seed) == {
        "team_provider_id": "42",
        "provider_position": "F",
        "provider_positions_detailed": ["ST"],
        "provider_preferred_foot": "right",
        "provider_height": 187,
        "provider_weight": 84,
    }
    assert PlayerPersistenceService._membership_metadata_fragment(seed) == {
        "provider_squad_number": 14,
        "provider_role": "ST",
        "provider_is_current": True,
    }
