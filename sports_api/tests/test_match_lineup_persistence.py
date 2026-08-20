import uuid
from datetime import UTC, datetime
from types import SimpleNamespace

from app.providers.base import ProviderMatchLineupEntrySeed, ProviderMatchLineupSeed, ProviderPlayerSeed
from app.services.match_lineup_persistence import MatchLineupPersistenceService


class DummySession:
    def __init__(self) -> None:
        self.added: list[object] = []

    def add(self, obj) -> None:
        self.added.append(obj)

    async def flush(self) -> None:
        return None


def test_normalize_statistics_payload_recursively_coerces_keys_and_values() -> None:
    payload = {
        "goalAssist": "2",
        "rating": "7.4",
        "statisticsType": "summary",
        "ratingVersions": {"original": "7.4", "alternative": "7.1"},
        "passing": {
            "accuratePass": "21",
            "totalPass": "25",
            "wasPressed": "false",
        },
        "tags": [" starter ", "2", "true"],
    }

    assert MatchLineupPersistenceService._normalize_statistics_payload(payload) == {
        "goal_assist": 2,
        "rating": 7.4,
        "statistics_type": "summary",
        "rating_versions": {"original": 7.4, "alternative": 7.1},
        "passing": {
            "accurate_pass": 21,
            "total_pass": 25,
            "was_pressed": False,
        },
        "tags": ["starter", 2, True],
    }


async def test_upsert_entry_stores_normalized_statistics(monkeypatch) -> None:
    service = MatchLineupPersistenceService(DummySession())
    provider = SimpleNamespace(id=uuid.uuid4())
    match = SimpleNamespace(id=uuid.uuid4())
    team = SimpleNamespace(id=uuid.uuid4())

    async def fake_upsert_player(*, provider, sync_run, seed):
        return SimpleNamespace(id=uuid.uuid4(), entity_uid=f"player:{seed.provider_player_id}")

    async def fake_upsert_team_membership(*, player, team, seed):
        return None

    monkeypatch.setattr(service.player_service, "_upsert_player", fake_upsert_player)
    monkeypatch.setattr(
        service.player_service,
        "_upsert_team_membership",
        fake_upsert_team_membership,
    )

    entry = ProviderMatchLineupEntrySeed(
        player=ProviderPlayerSeed(
            provider_player_id="804508",
            full_name="Viktor Gyokeres",
        ),
        team_side="home",
        is_starter=True,
        is_substitute=False,
        played=True,
        minutes_played=90,
        position="F",
        squad_number=14,
        statistics={
            "goals": "1",
            "rating": "7.4",
            "ratingVersions": {"original": "7.4"},
            "accuratePass": "21",
        },
        raw={"statistics": {"goals": "1"}},
    )

    await service._upsert_entry(
        provider=provider,
        sync_run=None,
        match=match,
        team=team,
        entry=entry,
        existing_appearances={},
    )

    appearance = service.session.added[0]
    assert appearance.metadata_json["statistics"] == entry.statistics
    assert appearance.metadata_json["normalized_statistics"] == {
        "goals": 1,
        "rating": 7.4,
        "rating_versions": {"original": 7.4},
        "accurate_pass": 21,
    }


def test_promote_starters_when_finished_match_has_no_participation_data() -> None:
    match = SimpleNamespace(
        status=SimpleNamespace(value="finished"),
        kickoff_at=datetime(2026, 4, 7, 2, 0, tzinfo=UTC),
    )
    lineup = ProviderMatchLineupSeed(
        provider_match_id="15706141",
        confirmed=True,
        home_players=[
            ProviderMatchLineupEntrySeed(
                player=ProviderPlayerSeed(provider_player_id="1001", full_name="Starter"),
                team_side="home",
                is_starter=True,
                is_substitute=False,
                played=False,
                statistics={},
            ),
            ProviderMatchLineupEntrySeed(
                player=ProviderPlayerSeed(provider_player_id="1002", full_name="Bench"),
                team_side="home",
                is_starter=False,
                is_substitute=True,
                played=False,
                statistics={},
            ),
        ],
        away_players=[],
        raw={},
    )

    MatchLineupPersistenceService._promote_starters_when_match_has_no_participation_data(
        match=match,
        lineup=lineup,
    )

    assert lineup.home_players[0].played is True
    assert lineup.home_players[1].played is False
