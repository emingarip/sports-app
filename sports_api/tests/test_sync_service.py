import uuid
from datetime import UTC, date, datetime
from types import SimpleNamespace

from app.db.models.domain import MatchStatus
from app.providers.base import (
    BootstrapCategorySeed,
    BootstrapSeasonSeed,
    BootstrapTournamentSeed,
    ProviderBatch,
    ProviderBootstrapCatalog,
    ProviderClient,
    ProviderMatchLineupEntrySeed,
    ProviderMatchLineupSeed,
    ProviderMatchSeed,
    ProviderPlayerSeed,
    ProviderTeamSeed,
)
from app.providers.hybrid import (
    HYBRID_LINEUP_PROVIDER_NAME,
    HYBRID_LINEUP_PROVIDER_SLUG,
)
from app.services.match_persistence import MatchPersistenceService
from app.services.sync_service import SyncService


class FakeProviderClient(ProviderClient):
    slug = "fake-provider"
    display_name = "Fake Provider"

    @property
    def base_url(self) -> str:
        return "https://fake.provider.local"

    async def fetch(self, *, scope, target_date):
        return ProviderBatch(scope=scope, target_date=target_date)

    async def bootstrap_catalog(self) -> ProviderBootstrapCatalog:
        return ProviderBootstrapCatalog(
            categories=[BootstrapCategorySeed(provider_category_id="1", name="England")],
            tournaments=[
                BootstrapTournamentSeed(
                    provider_tournament_id="100",
                    name="Premier League",
                    category_provider_id="1",
                )
            ],
            seasons=[
                BootstrapSeasonSeed(
                    provider_season_id="500",
                    tournament_provider_id="100",
                    name="2024/2025",
                )
            ],
        )

    async def get_extended_categories(self):
        return [BootstrapCategorySeed(provider_category_id="1", name="England")]

    async def get_team_players(self, team_provider_id: str):
        return [
            ProviderPlayerSeed(
                provider_player_id="804508",
                full_name="Viktor Gyokeres",
                short_name="V. Gyokeres",
                slug="viktor-gyokeres",
                team_provider_id=team_provider_id,
                squad_number=14,
                role="ST",
                is_current=True,
            )
        ]

    async def get_match_lineup(self, match_id: str):
        return ProviderMatchLineupSeed(
            provider_match_id=match_id,
            confirmed=True,
            home_players=[],
            away_players=[],
            raw={},
        )


class FakeResult:
    @staticmethod
    def scalar_one_or_none():
        return None


class FakeSession:
    def __init__(self) -> None:
        self.added = []
        self.rolled_back = False
        self.lookup = {}

    async def execute(self, _query):
        return FakeResult()

    def add(self, obj) -> None:
        self.added.append(obj)
        obj_id = getattr(obj, "id", None)
        if obj_id is not None:
            self.lookup[(type(obj), obj_id)] = obj

    async def flush(self) -> None:
        for obj in self.added:
            if getattr(obj, "id", None) is None:
                obj.id = uuid.uuid4()
            self.lookup[(type(obj), obj.id)] = obj

    async def commit(self) -> None:
        self.rolled_back = False
        return None

    async def refresh(self, _obj) -> None:
        return None

    async def rollback(self) -> None:
        self.rolled_back = True
        return None

    async def get(self, model, ident):
        value = self.lookup.get((model, ident))
        if value is not None:
            return value
        if getattr(model, "__name__", "") == "Team":
            return SimpleNamespace(id=ident)
        return None


async def test_sync_service_bootstrap_returns_stats(monkeypatch) -> None:
    from app.db.models.domain import Provider
    from app.providers.registry import REGISTERED_PROVIDER_CLIENTS

    session = FakeSession()
    service = SyncService(session)

    monkeypatch.setitem(REGISTERED_PROVIDER_CLIENTS, FakeProviderClient.slug, FakeProviderClient)

    provider = Provider(
        id=uuid.uuid4(),
        slug=FakeProviderClient.slug,
        name=FakeProviderClient.display_name,
        base_url="https://fake.provider.local",
        is_active=True,
        metadata_json={},
    )

    async def fake_get_or_create_provider(*, provider_slug: str, client):
        assert provider_slug == FakeProviderClient.slug
        assert client.base_url == "https://fake.provider.local"
        return provider

    class FakePersistStats:
        @staticmethod
        def to_dict():
            return {
                "countries_upserted": 1,
                "competitions_upserted": 1,
                "seasons_upserted": 1,
                "competition_seasons_upserted": 1,
                "mappings_upserted": 3,
                "raw_payloads_written": 3,
                "relations_upserted": 2,
            }

    async def fake_persist_catalog(self, *, provider, sync_run, catalog):
        assert provider.slug == FakeProviderClient.slug
        assert catalog.to_stats()["categories_count"] == 1
        return FakePersistStats()

    monkeypatch.setattr(service, "_get_or_create_provider", fake_get_or_create_provider)
    monkeypatch.setattr(
        "app.services.bootstrap_persistence.BootstrapPersistenceService.persist_catalog",
        fake_persist_catalog,
    )

    response = await service.trigger_provider_sync(
        provider_slug=FakeProviderClient.slug,
        scope="bootstrap-countries",
        target_date=None,
    )

    assert response.accepted is True
    assert response.status is not None
    assert response.status.value == "succeeded"
    assert response.stats == {
        "categories_count": 1,
        "tournaments_count": 0,
        "seasons_count": 0,
        "errors_count": 0,
        "countries_upserted": 1,
        "competitions_upserted": 1,
        "seasons_upserted": 1,
        "competition_seasons_upserted": 1,
        "mappings_upserted": 3,
        "raw_payloads_written": 3,
        "relations_upserted": 2,
    }
    assert response.queued_at is not None
    assert isinstance(response.queued_at, datetime)
    assert response.queued_at.tzinfo is UTC
    assert response.message == "Bootstrap stage completed."


async def test_sync_service_full_bootstrap_is_disabled(monkeypatch) -> None:
    from app.db.models.domain import Provider
    from app.providers.registry import REGISTERED_PROVIDER_CLIENTS

    session = FakeSession()
    service = SyncService(session)

    monkeypatch.setitem(REGISTERED_PROVIDER_CLIENTS, FakeProviderClient.slug, FakeProviderClient)

    provider = Provider(
        id=uuid.uuid4(),
        slug=FakeProviderClient.slug,
        name=FakeProviderClient.display_name,
        base_url="https://fake.provider.local",
        is_active=True,
        metadata_json={},
    )

    async def fake_get_or_create_provider(*, provider_slug: str, client):
        assert provider_slug == FakeProviderClient.slug
        assert client.base_url == "https://fake.provider.local"
        return provider

    monkeypatch.setattr(service, "_get_or_create_provider", fake_get_or_create_provider)

    response = await service.trigger_provider_sync(
        provider_slug=FakeProviderClient.slug,
        scope="bootstrap",
        target_date=None,
    )

    assert response.accepted is False
    assert response.status is not None
    assert response.status.value == "failed"
    assert "Full bootstrap is disabled" in response.message


async def test_sync_service_matches_returns_stats(monkeypatch) -> None:
    from app.db.models.domain import Provider
    from app.providers.registry import REGISTERED_PROVIDER_CLIENTS

    session = FakeSession()
    service = SyncService(session)

    monkeypatch.setitem(REGISTERED_PROVIDER_CLIENTS, FakeProviderClient.slug, FakeProviderClient)

    provider = Provider(
        id=uuid.uuid4(),
        slug=FakeProviderClient.slug,
        name=FakeProviderClient.display_name,
        base_url="https://fake.provider.local",
        is_active=True,
        metadata_json={},
    )

    async def fake_get_or_create_provider(*, provider_slug: str, client):
        assert provider_slug == FakeProviderClient.slug
        assert client.base_url == "https://fake.provider.local"
        return provider

    async def fake_fetch(self, *, scope, target_date):
        assert scope == "matches"
        assert target_date == date(2026, 4, 6)
        return ProviderBatch(
            scope=scope,
            target_date=target_date,
            matches=[
                ProviderMatchSeed(
                    provider_match_id="14025056",
                    kickoff_at=datetime(2026, 4, 6, 1, 30, tzinfo=UTC),
                    status="finished",
                    provider_status="Ended",
                    home_team=ProviderTeamSeed(provider_team_id="1", name="Home FC"),
                    away_team=ProviderTeamSeed(provider_team_id="2", name="Away FC"),
                )
            ],
        )

    async def fake_persist_batch(self, *, provider, sync_run, batch):
        assert provider.slug == FakeProviderClient.slug
        assert len(batch.matches) == 1
        return {
            "countries_upserted": 1,
            "competitions_upserted": 1,
            "seasons_upserted": 1,
            "competition_seasons_upserted": 1,
            "teams_upserted": 2,
            "matches_upserted": 1,
            "mappings_upserted": 5,
            "raw_payloads_written": 5,
            "relations_upserted": 3,
        }

    monkeypatch.setattr(service, "_get_or_create_provider", fake_get_or_create_provider)
    monkeypatch.setattr(FakeProviderClient, "fetch", fake_fetch)
    monkeypatch.setattr(
        "app.services.match_persistence.MatchPersistenceService.persist_batch",
        fake_persist_batch,
    )

    response = await service.trigger_provider_sync(
        provider_slug=FakeProviderClient.slug,
        scope="matches",
        target_date=date(2026, 4, 6),
    )

    assert response.accepted is True
    assert response.status is not None
    assert response.status.value == "succeeded"
    assert response.stats == {
        "matches_count": 1,
        "countries_upserted": 1,
        "competitions_upserted": 1,
        "seasons_upserted": 1,
        "competition_seasons_upserted": 1,
        "teams_upserted": 2,
        "matches_upserted": 1,
        "mappings_upserted": 5,
        "raw_payloads_written": 5,
        "relations_upserted": 3,
    }
    assert response.target_date == date(2026, 4, 6)
    assert response.message == "Match sync completed."


async def test_sync_service_matches_failure_recovers_after_rollback(monkeypatch) -> None:
    from app.db.models.domain import Provider
    from app.providers.registry import REGISTERED_PROVIDER_CLIENTS

    class ExpiringProvider:
        def __init__(self, session: FakeSession, provider_id: uuid.UUID) -> None:
            self._session = session
            self._id = provider_id
            self.slug = FakeProviderClient.slug
            self.name = FakeProviderClient.display_name
            self.base_url = "https://fake.provider.local"

        @property
        def id(self) -> uuid.UUID:
            if self._session.rolled_back:
                raise RuntimeError("stale provider access after rollback")
            return self._id

    session = FakeSession()
    service = SyncService(session)

    monkeypatch.setitem(REGISTERED_PROVIDER_CLIENTS, FakeProviderClient.slug, FakeProviderClient)

    expiring_provider = ExpiringProvider(session, uuid.uuid4())
    recovered_provider = Provider(
        id=uuid.uuid4(),
        slug=FakeProviderClient.slug,
        name=FakeProviderClient.display_name,
        base_url="https://fake.provider.local",
        is_active=True,
        metadata_json={},
    )
    provider_calls = 0

    async def fake_get_or_create_provider(*, provider_slug: str, client):
        nonlocal provider_calls
        assert provider_slug == FakeProviderClient.slug
        provider_calls += 1
        if provider_calls == 1:
            return expiring_provider
        return recovered_provider

    async def fake_fetch(self, *, scope, target_date):
        assert scope == "matches"
        assert target_date == date(2026, 4, 6)
        return ProviderBatch(
            scope=scope,
            target_date=target_date,
            matches=[
                ProviderMatchSeed(
                    provider_match_id="14025056",
                    kickoff_at=datetime(2026, 4, 6, 1, 30, tzinfo=UTC),
                    status="finished",
                    provider_status="Ended",
                    home_team=ProviderTeamSeed(provider_team_id="1", name="Home FC"),
                    away_team=ProviderTeamSeed(provider_team_id="2", name="Away FC"),
                )
            ],
        )

    async def fake_persist_batch(self, *, provider, sync_run, batch):
        raise RuntimeError("boom")

    monkeypatch.setattr(service, "_get_or_create_provider", fake_get_or_create_provider)
    monkeypatch.setattr(FakeProviderClient, "fetch", fake_fetch)
    monkeypatch.setattr(
        "app.services.match_persistence.MatchPersistenceService.persist_batch",
        fake_persist_batch,
    )

    response = await service.trigger_provider_sync(
        provider_slug=FakeProviderClient.slug,
        scope="matches",
        target_date=date(2026, 4, 6),
    )

    assert response.accepted is False
    assert response.status is not None
    assert response.status.value == "failed"
    assert response.message == "Match sync failed: boom"
    assert response.target_date == date(2026, 4, 6)
    assert provider_calls == 2


async def test_sync_service_players_returns_stats(monkeypatch) -> None:
    from app.db.models.domain import Provider
    from app.providers.registry import REGISTERED_PROVIDER_CLIENTS

    session = FakeSession()
    service = SyncService(session)

    monkeypatch.setitem(REGISTERED_PROVIDER_CLIENTS, FakeProviderClient.slug, FakeProviderClient)

    provider = Provider(
        id=uuid.uuid4(),
        slug=FakeProviderClient.slug,
        name=FakeProviderClient.display_name,
        base_url="https://fake.provider.local",
        is_active=True,
        metadata_json={},
    )

    async def fake_get_or_create_provider(*, provider_slug: str, client):
        assert provider_slug == FakeProviderClient.slug
        return provider

    async def fake_get_provider_team_mappings(*, provider):
        return [(SimpleNamespace(id=uuid.uuid4(), entity_uid="team:1", name="Arsenal"), "42")]

    async def fake_persist_team_players(self, *, provider, sync_run, team, team_provider_id, seeds):
        assert provider.slug == FakeProviderClient.slug
        assert team_provider_id == "42"
        assert len(seeds) == 1
        self.catalog.stats.countries_upserted = 1
        self.stats.players_upserted = 1
        self.stats.memberships_upserted = 1
        self.stats.mappings_upserted = 1
        self.stats.raw_payloads_written = 1
        return {}

    monkeypatch.setattr(service, "_get_or_create_provider", fake_get_or_create_provider)
    monkeypatch.setattr(service, "_get_provider_team_mappings", fake_get_provider_team_mappings)
    monkeypatch.setattr(
        "app.services.player_persistence.PlayerPersistenceService.persist_team_players",
        fake_persist_team_players,
    )

    response = await service.trigger_provider_sync(
        provider_slug=FakeProviderClient.slug,
        scope="players",
        target_date=None,
    )

    assert response.accepted is True
    assert response.status is not None
    assert response.status.value == "succeeded"
    assert response.stats is not None
    assert response.stats["teams_total_mapped"] == 1
    assert response.stats["teams_scanned"] == 1
    assert response.stats["players_fetched"] == 1
    assert response.stats["countries_upserted"] == 1
    assert response.stats["players_upserted"] == 1
    assert response.stats["memberships_upserted"] == 1
    assert response.stats["mappings_upserted"] == 1
    assert response.stats["raw_payloads_written"] == 1
    assert response.stats["teams_failed"] == 0
    assert response.message == "Player sync completed."


async def test_sync_service_players_requires_mapped_teams(monkeypatch) -> None:
    from app.db.models.domain import Provider
    from app.providers.registry import REGISTERED_PROVIDER_CLIENTS

    session = FakeSession()
    service = SyncService(session)

    monkeypatch.setitem(REGISTERED_PROVIDER_CLIENTS, FakeProviderClient.slug, FakeProviderClient)

    provider = Provider(
        id=uuid.uuid4(),
        slug=FakeProviderClient.slug,
        name=FakeProviderClient.display_name,
        base_url="https://fake.provider.local",
        is_active=True,
        metadata_json={},
    )

    async def fake_get_or_create_provider(*, provider_slug: str, client):
        return provider

    async def fake_get_provider_team_mappings(*, provider):
        return []

    monkeypatch.setattr(service, "_get_or_create_provider", fake_get_or_create_provider)
    monkeypatch.setattr(service, "_get_provider_team_mappings", fake_get_provider_team_mappings)

    response = await service.trigger_provider_sync(
        provider_slug=FakeProviderClient.slug,
        scope="players",
        target_date=None,
    )

    assert response.accepted is False
    assert response.status is not None
    assert response.status.value == "failed"
    assert "Run match sync first" in response.message


async def test_sync_service_players_skips_missing_team_rosters(monkeypatch) -> None:
    from app.db.models.domain import Provider
    from app.providers.registry import REGISTERED_PROVIDER_CLIENTS

    class FakeRosterError(RuntimeError):
        def __init__(self, status_code: int) -> None:
            super().__init__(f"status={status_code}")
            self.status_code = status_code

    session = FakeSession()
    service = SyncService(session)

    monkeypatch.setitem(REGISTERED_PROVIDER_CLIENTS, FakeProviderClient.slug, FakeProviderClient)

    provider = Provider(
        id=uuid.uuid4(),
        slug=FakeProviderClient.slug,
        name=FakeProviderClient.display_name,
        base_url="https://fake.provider.local",
        is_active=True,
        metadata_json={},
    )

    async def fake_get_or_create_provider(*, provider_slug: str, client):
        return provider

    async def fake_get_provider_team_mappings(*, provider):
        return [
            (SimpleNamespace(id=uuid.uuid4(), entity_uid="team:missing", name="Missing FC"), "404"),
            (SimpleNamespace(id=uuid.uuid4(), entity_uid="team:ok", name="Arsenal"), "42"),
        ]

    async def fake_get_team_players(self, team_provider_id: str):
        if team_provider_id == "404":
            raise FakeRosterError(404)
        return [
            ProviderPlayerSeed(
                provider_player_id="804508",
                full_name="Viktor Gyokeres",
                short_name="V. Gyokeres",
                slug="viktor-gyokeres",
                team_provider_id=team_provider_id,
                squad_number=14,
                role="ST",
                is_current=True,
            )
        ]

    async def fake_persist_team_players(self, *, provider, sync_run, team, team_provider_id, seeds):
        assert team_provider_id == "42"
        assert len(seeds) == 1
        self.stats.players_upserted = 1
        self.stats.memberships_upserted = 1
        self.stats.mappings_upserted = 1
        self.stats.raw_payloads_written = 1
        return {}

    monkeypatch.setattr(service, "_get_or_create_provider", fake_get_or_create_provider)
    monkeypatch.setattr(service, "_get_provider_team_mappings", fake_get_provider_team_mappings)
    monkeypatch.setattr(FakeProviderClient, "get_team_players", fake_get_team_players)
    monkeypatch.setattr(
        "app.services.player_persistence.PlayerPersistenceService.persist_team_players",
        fake_persist_team_players,
    )

    response = await service.trigger_provider_sync(
        provider_slug=FakeProviderClient.slug,
        scope="players",
        target_date=None,
    )

    assert response.accepted is True
    assert response.status is not None
    assert response.status.value == "succeeded"
    assert response.stats is not None
    assert response.stats["teams_total_mapped"] == 2
    assert response.stats["teams_scanned"] == 2
    assert response.stats["teams_synced"] == 1
    assert response.stats["teams_missing_roster"] == 1
    assert response.stats["teams_failed"] == 0
    assert response.stats["players_fetched"] == 1
    assert response.message == "Player sync completed: skipped 1 missing rosters."


async def test_sync_service_match_lineups_returns_stats(monkeypatch) -> None:
    from app.db.models.domain import Provider
    from app.providers.registry import REGISTERED_PROVIDER_CLIENTS

    session = FakeSession()
    service = SyncService(session)

    monkeypatch.setitem(REGISTERED_PROVIDER_CLIENTS, FakeProviderClient.slug, FakeProviderClient)

    provider = Provider(
        id=uuid.uuid4(),
        slug=FakeProviderClient.slug,
        name=FakeProviderClient.display_name,
        base_url="https://fake.provider.local",
        is_active=True,
        metadata_json={},
    )
    match_id = uuid.uuid4()

    async def fake_get_or_create_provider(*, provider_slug: str, client):
        assert provider_slug == FakeProviderClient.slug
        return provider

    async def fake_get_provider_match_mappings(*, provider, target_date, timezone_name):
        assert target_date == date(2026, 4, 6)
        assert timezone_name == "Europe/Istanbul"
        return [(SimpleNamespace(id=match_id), "14025056")]

    async def fake_get_match_for_lineup_sync(found_match_id):
        assert found_match_id == match_id
        return SimpleNamespace(
            id=match_id,
            home_team=SimpleNamespace(id=uuid.uuid4(), name="Home FC"),
            away_team=SimpleNamespace(id=uuid.uuid4(), name="Away FC"),
            metadata_json={},
        )

    async def fake_get_match_lineup(self, match_id: str):
        assert match_id == "14025056"
        return ProviderMatchLineupSeed(
            provider_match_id=match_id,
            confirmed=True,
            home_players=[
                ProviderMatchLineupEntrySeed(
                    player=ProviderPlayerSeed(
                        provider_player_id="804508",
                        full_name="Viktor Gyokeres",
                    ),
                    team_side="home",
                    is_starter=True,
                    is_substitute=False,
                    played=True,
                )
            ],
            away_players=[],
            raw={},
        )

    async def fake_persist_match_lineup(self, *, provider, sync_run, match, lineup):
        assert provider.slug == FakeProviderClient.slug
        assert match.id == match_id
        assert lineup.provider_match_id == "14025056"
        self.player_service.stats.players_upserted = 1
        self.stats.appearances_upserted = 1
        self.stats.raw_payloads_written = 1
        return {}

    monkeypatch.setattr(service, "_get_or_create_provider", fake_get_or_create_provider)
    monkeypatch.setattr(service, "_get_provider_match_mappings", fake_get_provider_match_mappings)
    monkeypatch.setattr(service, "_get_match_for_lineup_sync", fake_get_match_for_lineup_sync)
    monkeypatch.setattr(FakeProviderClient, "get_match_lineup", fake_get_match_lineup)
    monkeypatch.setattr(
        "app.services.match_lineup_persistence.MatchLineupPersistenceService.persist_match_lineup",
        fake_persist_match_lineup,
    )

    response = await service.trigger_provider_sync(
        provider_slug=FakeProviderClient.slug,
        scope="match-lineups",
        target_date=date(2026, 4, 6),
        timezone_name="Europe/Istanbul",
    )

    assert response.accepted is True
    assert response.status is not None
    assert response.status.value == "succeeded"
    assert response.stats is not None
    assert response.stats["matches_total"] == 1
    assert response.stats["matches_scanned"] == 1
    assert response.stats["matches_with_lineups"] == 1
    assert response.stats["matches_missing_lineups"] == 0
    assert response.stats["matches_failed"] == 0
    assert response.stats["players_upserted"] == 1
    assert response.stats["appearances_upserted"] == 1
    assert response.message == "Match lineup sync completed."


async def test_sync_service_match_lineup_sync_marks_missing_lineup(monkeypatch) -> None:
    from app.db.models.domain import Provider
    from app.providers.registry import REGISTERED_PROVIDER_CLIENTS

    session = FakeSession()
    service = SyncService(session)

    monkeypatch.setitem(REGISTERED_PROVIDER_CLIENTS, FakeProviderClient.slug, FakeProviderClient)

    provider = Provider(
        id=uuid.uuid4(),
        slug=FakeProviderClient.slug,
        name=FakeProviderClient.display_name,
        base_url="https://fake.provider.local",
        is_active=True,
        metadata_json={},
    )
    match_id = uuid.uuid4()

    async def fake_get_or_create_provider(*, provider_slug: str, client):
        assert provider_slug == FakeProviderClient.slug
        return provider

    async def fake_get_provider_match_mappings(*, provider, target_date, timezone_name):
        assert target_date == date(2026, 4, 6)
        assert timezone_name == "Europe/Istanbul"
        return [(SimpleNamespace(id=match_id), "15898306")]

    async def fake_get_match_for_lineup_sync(found_match_id):
        assert found_match_id == match_id
        return SimpleNamespace(
            id=match_id,
            home_team=SimpleNamespace(id=uuid.uuid4(), name="Home FC"),
            away_team=SimpleNamespace(id=uuid.uuid4(), name="Away FC"),
            metadata_json={},
        )

    async def fake_get_match_lineup(self, match_id: str):
        assert match_id == "15898306"
        return None

    async def fake_persist_missing_match_lineup(
        self,
        *,
        provider,
        sync_run,
        match,
        provider_match_id,
        reason="no_lineup",
    ):
        assert provider.slug == FakeProviderClient.slug
        assert match.id == match_id
        assert provider_match_id == "15898306"
        assert reason == "no_lineup"
        self.stats.matches_marked_no_lineup = 1
        return {}

    monkeypatch.setattr(service, "_get_or_create_provider", fake_get_or_create_provider)
    monkeypatch.setattr(service, "_get_provider_match_mappings", fake_get_provider_match_mappings)
    monkeypatch.setattr(service, "_get_match_for_lineup_sync", fake_get_match_for_lineup_sync)
    monkeypatch.setattr(FakeProviderClient, "get_match_lineup", fake_get_match_lineup)
    monkeypatch.setattr(
        "app.services.match_lineup_persistence.MatchLineupPersistenceService.persist_missing_match_lineup",
        fake_persist_missing_match_lineup,
    )

    response = await service.trigger_provider_sync(
        provider_slug=FakeProviderClient.slug,
        scope="match-lineups",
        target_date=date(2026, 4, 6),
        timezone_name="Europe/Istanbul",
    )

    assert response.accepted is True
    assert response.status is not None
    assert response.status.value == "succeeded"
    assert response.stats is not None
    assert response.stats["matches_total"] == 1
    assert response.stats["matches_scanned"] == 1
    assert response.stats["matches_with_lineups"] == 0
    assert response.stats["matches_missing_lineups"] == 1
    assert response.stats["matches_failed"] == 0
    assert response.message == "Match lineup sync completed: skipped 1 missing lineups."


async def test_sync_service_hybrid_match_lineups_falls_back_to_sofascore(monkeypatch) -> None:
    from app.db.models.domain import Provider

    session = FakeSession()
    service = SyncService(session)

    provider = Provider(
        id=uuid.uuid4(),
        slug=HYBRID_LINEUP_PROVIDER_SLUG,
        name=HYBRID_LINEUP_PROVIDER_NAME,
        base_url=None,
        is_active=True,
        metadata_json={},
    )
    match_id = uuid.uuid4()
    match_record = SimpleNamespace(
        id=match_id,
        home_team=SimpleNamespace(id=uuid.uuid4(), name="Home FC"),
        away_team=SimpleNamespace(id=uuid.uuid4(), name="Away FC"),
        metadata_json={},
    )

    class FailingSportsApiClient:
        async def get_match_lineup(self, match_id: str):
            assert match_id == "15265728"
            raise RuntimeError("sportsapipro lineup failed")

        async def aclose(self):
            return None

    class SofascoreClient:
        async def get_match_lineup(self, match_id: str):
            assert match_id == "15820475"
            return ProviderMatchLineupSeed(
                provider_match_id=match_id,
                confirmed=True,
                home_players=[
                    ProviderMatchLineupEntrySeed(
                        player=ProviderPlayerSeed(
                            provider_player_id="804508",
                            full_name="Viktor Gyokeres",
                        ),
                        team_side="home",
                        is_starter=True,
                        is_substitute=False,
                        played=True,
                    )
                ],
                away_players=[],
                raw={},
            )

        async def aclose(self):
            return None

    async def fake_get_or_create_provider(
        *,
        provider_slug: str,
        client,
        provider_name: str | None = None,
        base_url: str | None = None,
    ):
        assert provider_slug == HYBRID_LINEUP_PROVIDER_SLUG
        assert provider_name == HYBRID_LINEUP_PROVIDER_NAME
        return provider

    async def fake_get_provider_match_mappings_for_provider_slugs(
        *,
        provider_slugs,
        target_date,
        timezone_name,
    ):
        assert target_date == date(2026, 4, 6)
        assert timezone_name == "Europe/Istanbul"
        assert HYBRID_LINEUP_PROVIDER_SLUG in provider_slugs
        return [
            (
                match_record,
                {
                    "sportsapipro-football-v2": "15265728",
                    "sofascore-football": "15820475",
                },
            )
        ]

    def fake_build_provider_client(provider_slug: str, *, settings, progress_callback=None):
        if provider_slug == "sportsapipro-football-v2":
            return FailingSportsApiClient()
        if provider_slug == "sofascore-football":
            return SofascoreClient()
        raise AssertionError(provider_slug)

    async def fake_persist_match_lineup(
        self,
        *,
        provider,
        sync_run,
        match,
        lineup,
        source_provider_slug=None,
        source_provider_match_id=None,
    ):
        assert provider.slug == HYBRID_LINEUP_PROVIDER_SLUG
        assert match.id == match_id
        assert lineup.provider_match_id == "15820475"
        assert source_provider_slug == "sofascore-football"
        assert source_provider_match_id == "15820475"
        self.player_service.stats.players_upserted = 1
        self.stats.appearances_upserted = 1
        self.stats.raw_payloads_written = 1
        return {}

    monkeypatch.setattr(service, "_get_or_create_provider", fake_get_or_create_provider)
    monkeypatch.setattr(
        service,
        "_get_provider_match_mappings_for_provider_slugs",
        fake_get_provider_match_mappings_for_provider_slugs,
    )
    monkeypatch.setattr(service, "_build_provider_client", fake_build_provider_client)
    monkeypatch.setattr(
        "app.services.match_lineup_persistence.MatchLineupPersistenceService.persist_match_lineup",
        fake_persist_match_lineup,
    )

    response = await service.trigger_provider_sync(
        provider_slug=HYBRID_LINEUP_PROVIDER_SLUG,
        scope="match-lineups",
        target_date=date(2026, 4, 6),
        timezone_name="Europe/Istanbul",
    )

    assert response.accepted is True
    assert response.status is not None
    assert response.status.value == "succeeded"
    assert response.stats is not None
    assert response.stats["matches_total"] == 1
    assert response.stats["matches_scanned"] == 1
    assert response.stats["matches_with_lineups"] == 1
    assert response.stats["matches_missing_lineups"] == 0
    assert response.stats["matches_failed"] == 0
    assert response.message == "Match lineup sync completed."


async def test_sync_service_hybrid_match_lineups_falls_back_when_primary_has_zero_played(
    monkeypatch,
) -> None:
    from app.db.models.domain import Provider

    session = FakeSession()
    service = SyncService(session)

    provider = Provider(
        id=uuid.uuid4(),
        slug=HYBRID_LINEUP_PROVIDER_SLUG,
        name=HYBRID_LINEUP_PROVIDER_NAME,
        base_url=None,
        is_active=True,
        metadata_json={},
    )
    match_id = uuid.uuid4()
    match_record = SimpleNamespace(
        id=match_id,
        status=SimpleNamespace(value="finished"),
        home_team=SimpleNamespace(id=uuid.uuid4(), name="Home FC"),
        away_team=SimpleNamespace(id=uuid.uuid4(), name="Away FC"),
        metadata_json={},
    )

    class LowQualitySportsApiClient:
        async def get_match_lineup(self, match_id: str):
            assert match_id == "15265728"
            return ProviderMatchLineupSeed(
                provider_match_id=match_id,
                confirmed=True,
                home_players=[
                    ProviderMatchLineupEntrySeed(
                        player=ProviderPlayerSeed(
                            provider_player_id="1001",
                            full_name="Home Player",
                        ),
                        team_side="home",
                        is_starter=True,
                        is_substitute=False,
                        played=False,
                    )
                ],
                away_players=[
                    ProviderMatchLineupEntrySeed(
                        player=ProviderPlayerSeed(
                            provider_player_id="2001",
                            full_name="Away Player",
                        ),
                        team_side="away",
                        is_starter=True,
                        is_substitute=False,
                        played=False,
                    )
                ],
                raw={},
            )

        async def aclose(self):
            return None

    class SofascoreClient:
        async def get_match_lineup(self, match_id: str):
            assert match_id == "15820475"
            return ProviderMatchLineupSeed(
                provider_match_id=match_id,
                confirmed=True,
                home_players=[
                    ProviderMatchLineupEntrySeed(
                        player=ProviderPlayerSeed(
                            provider_player_id="804508",
                            full_name="Viktor Gyokeres",
                        ),
                        team_side="home",
                        is_starter=True,
                        is_substitute=False,
                        played=True,
                        minutes_played=90,
                    )
                ],
                away_players=[],
                raw={},
            )

        async def aclose(self):
            return None

    async def fake_get_or_create_provider(
        *,
        provider_slug: str,
        client,
        provider_name: str | None = None,
        base_url: str | None = None,
    ):
        assert provider_slug == HYBRID_LINEUP_PROVIDER_SLUG
        assert provider_name == HYBRID_LINEUP_PROVIDER_NAME
        return provider

    async def fake_get_provider_match_mappings_for_provider_slugs(
        *,
        provider_slugs,
        target_date,
        timezone_name,
    ):
        assert target_date == date(2026, 4, 6)
        assert timezone_name == "Europe/Istanbul"
        assert HYBRID_LINEUP_PROVIDER_SLUG in provider_slugs
        return [
            (
                match_record,
                {
                    "sportsapipro-football-v2": "15265728",
                    "sofascore-football": "15820475",
                },
            )
        ]

    def fake_build_provider_client(provider_slug: str, *, settings, progress_callback=None):
        if provider_slug == "sportsapipro-football-v2":
            return LowQualitySportsApiClient()
        if provider_slug == "sofascore-football":
            return SofascoreClient()
        raise AssertionError(provider_slug)

    async def fake_persist_match_lineup(
        self,
        *,
        provider,
        sync_run,
        match,
        lineup,
        source_provider_slug=None,
        source_provider_match_id=None,
    ):
        assert provider.slug == HYBRID_LINEUP_PROVIDER_SLUG
        assert match.id == match_id
        assert lineup.provider_match_id == "15820475"
        assert source_provider_slug == "sofascore-football"
        assert source_provider_match_id == "15820475"
        self.player_service.stats.players_upserted = 1
        self.stats.appearances_upserted = 1
        self.stats.raw_payloads_written = 1
        return {}

    monkeypatch.setattr(service, "_get_or_create_provider", fake_get_or_create_provider)
    monkeypatch.setattr(
        service,
        "_get_provider_match_mappings_for_provider_slugs",
        fake_get_provider_match_mappings_for_provider_slugs,
    )
    monkeypatch.setattr(service, "_build_provider_client", fake_build_provider_client)
    monkeypatch.setattr(
        "app.services.match_lineup_persistence.MatchLineupPersistenceService.persist_match_lineup",
        fake_persist_match_lineup,
    )

    response = await service.trigger_provider_sync(
        provider_slug=HYBRID_LINEUP_PROVIDER_SLUG,
        scope="match-lineups",
        target_date=date(2026, 4, 6),
        timezone_name="Europe/Istanbul",
    )

    assert response.accepted is True
    assert response.status is not None
    assert response.status.value == "succeeded"
    assert response.stats is not None
    assert response.stats["matches_total"] == 1
    assert response.stats["matches_scanned"] == 1
    assert response.stats["matches_with_lineups"] == 1
    assert response.stats["matches_missing_lineups"] == 0
    assert response.stats["matches_failed"] == 0
    assert response.message == "Match lineup sync completed."


async def test_sync_service_hybrid_match_lineups_falls_back_when_status_is_stale_scheduled(
    monkeypatch,
) -> None:
    from app.db.models.domain import Provider

    session = FakeSession()
    service = SyncService(session)

    provider = Provider(
        id=uuid.uuid4(),
        slug=HYBRID_LINEUP_PROVIDER_SLUG,
        name=HYBRID_LINEUP_PROVIDER_NAME,
        base_url=None,
        is_active=True,
        metadata_json={},
    )
    match_id = uuid.uuid4()
    match_record = SimpleNamespace(
        id=match_id,
        status=SimpleNamespace(value="scheduled"),
        kickoff_at=datetime(2000, 1, 1, 18, 0, tzinfo=UTC),
        home_team=SimpleNamespace(id=uuid.uuid4(), name="Municipal Liberia"),
        away_team=SimpleNamespace(id=uuid.uuid4(), name="San Carlos"),
        metadata_json={},
    )

    class LowQualitySportsApiClient:
        async def get_match_lineup(self, match_id: str):
            assert match_id == "15265728"
            return ProviderMatchLineupSeed(
                provider_match_id=match_id,
                confirmed=True,
                home_players=[
                    ProviderMatchLineupEntrySeed(
                        player=ProviderPlayerSeed(
                            provider_player_id="1001",
                            full_name="Home Player",
                        ),
                        team_side="home",
                        is_starter=True,
                        is_substitute=False,
                        played=False,
                    )
                ],
                away_players=[
                    ProviderMatchLineupEntrySeed(
                        player=ProviderPlayerSeed(
                            provider_player_id="2001",
                            full_name="Away Player",
                        ),
                        team_side="away",
                        is_starter=True,
                        is_substitute=False,
                        played=False,
                    )
                ],
                raw={},
            )

        async def aclose(self):
            return None

    class SofascoreClient:
        async def get_match_lineup(self, match_id: str):
            assert match_id == "15820475"
            return ProviderMatchLineupSeed(
                provider_match_id=match_id,
                confirmed=True,
                home_players=[
                    ProviderMatchLineupEntrySeed(
                        player=ProviderPlayerSeed(
                            provider_player_id="804508",
                            full_name="Home Player",
                        ),
                        team_side="home",
                        is_starter=True,
                        is_substitute=False,
                        played=True,
                        minutes_played=90,
                    )
                ],
                away_players=[
                    ProviderMatchLineupEntrySeed(
                        player=ProviderPlayerSeed(
                            provider_player_id="9001",
                            full_name="Away Player",
                        ),
                        team_side="away",
                        is_starter=True,
                        is_substitute=False,
                        played=True,
                        minutes_played=90,
                    )
                ],
                raw={},
            )

        async def aclose(self):
            return None

    async def fake_get_or_create_provider(
        *,
        provider_slug: str,
        client,
        provider_name: str | None = None,
        base_url: str | None = None,
    ):
        assert provider_slug == HYBRID_LINEUP_PROVIDER_SLUG
        assert provider_name == HYBRID_LINEUP_PROVIDER_NAME
        return provider

    async def fake_get_provider_match_mappings_for_provider_slugs(
        *,
        provider_slugs,
        target_date,
        timezone_name,
    ):
        assert target_date == date(2026, 4, 6)
        assert timezone_name == "Europe/Istanbul"
        assert HYBRID_LINEUP_PROVIDER_SLUG in provider_slugs
        return [
            (
                match_record,
                {
                    "sportsapipro-football-v2": "15265728",
                    "sofascore-football": "15820475",
                },
            )
        ]

    def fake_build_provider_client(provider_slug: str, *, settings, progress_callback=None):
        if provider_slug == "sportsapipro-football-v2":
            return LowQualitySportsApiClient()
        if provider_slug == "sofascore-football":
            return SofascoreClient()
        raise AssertionError(provider_slug)

    async def fake_persist_match_lineup(
        self,
        *,
        provider,
        sync_run,
        match,
        lineup,
        source_provider_slug=None,
        source_provider_match_id=None,
    ):
        assert provider.slug == HYBRID_LINEUP_PROVIDER_SLUG
        assert match.id == match_id
        assert lineup.provider_match_id == "15820475"
        assert source_provider_slug == "sofascore-football"
        assert source_provider_match_id == "15820475"
        self.player_service.stats.players_upserted = 2
        self.stats.appearances_upserted = 2
        self.stats.raw_payloads_written = 1
        return {}

    monkeypatch.setattr(service, "_get_or_create_provider", fake_get_or_create_provider)
    monkeypatch.setattr(
        service,
        "_get_provider_match_mappings_for_provider_slugs",
        fake_get_provider_match_mappings_for_provider_slugs,
    )
    monkeypatch.setattr(service, "_build_provider_client", fake_build_provider_client)
    monkeypatch.setattr(
        "app.services.match_lineup_persistence.MatchLineupPersistenceService.persist_match_lineup",
        fake_persist_match_lineup,
    )

    response = await service.trigger_provider_sync(
        provider_slug=HYBRID_LINEUP_PROVIDER_SLUG,
        scope="match-lineups",
        target_date=date(2026, 4, 6),
        timezone_name="Europe/Istanbul",
    )

    assert response.accepted is True
    assert response.status is not None
    assert response.status.value == "succeeded"
    assert response.stats is not None
    assert response.stats["matches_total"] == 1
    assert response.stats["matches_scanned"] == 1
    assert response.stats["matches_with_lineups"] == 1
    assert response.stats["matches_missing_lineups"] == 0
    assert response.stats["matches_failed"] == 0
    assert response.message == "Match lineup sync completed."


async def test_sync_service_hybrid_match_lineups_uses_validated_implicit_sofascore_id(
    monkeypatch,
) -> None:
    from app.db.models.domain import Provider

    session = FakeSession()
    service = SyncService(session)

    provider = Provider(
        id=uuid.uuid4(),
        slug=HYBRID_LINEUP_PROVIDER_SLUG,
        name=HYBRID_LINEUP_PROVIDER_NAME,
        base_url=None,
        is_active=True,
        metadata_json={},
    )
    match_id = uuid.uuid4()
    match_record = SimpleNamespace(
        id=match_id,
        status=SimpleNamespace(value="finished"),
        home_team=SimpleNamespace(id=uuid.uuid4(), name="Finland U21"),
        away_team=SimpleNamespace(id=uuid.uuid4(), name="Cyprus U21"),
        metadata_json={
            "raw": {
                "id": 13500811,
                "startTimestamp": 1774969200,
                "homeTeam": {"id": 6027, "name": "Finland U21"},
                "awayTeam": {"id": 6021, "name": "Cyprus U21"},
            }
        },
    )

    class MissingSportsApiClient:
        async def get_match_lineup(self, match_id: str):
            assert match_id == "13500811"
            return None

        async def aclose(self):
            return None

    class SofascoreClient:
        async def get_match_event(self, match_id: str):
            assert match_id == "13500811"
            return {
                "id": 13500811,
                "startTimestamp": 1774969200,
                "homeTeam": {"id": 6027, "name": "Finland U21"},
                "awayTeam": {"id": 6021, "name": "Cyprus U21"},
            }

        async def get_match_lineup(self, match_id: str):
            assert match_id == "13500811"
            return ProviderMatchLineupSeed(
                provider_match_id=match_id,
                confirmed=True,
                home_players=[
                    ProviderMatchLineupEntrySeed(
                        player=ProviderPlayerSeed(
                            provider_player_id="1001",
                            full_name="Home Player",
                        ),
                        team_side="home",
                        is_starter=True,
                        is_substitute=False,
                        played=True,
                    )
                ],
                away_players=[],
                raw={},
            )

        async def aclose(self):
            return None

    async def fake_get_or_create_provider(
        *,
        provider_slug: str,
        client,
        provider_name: str | None = None,
        base_url: str | None = None,
    ):
        assert provider_slug == HYBRID_LINEUP_PROVIDER_SLUG
        assert provider_name == HYBRID_LINEUP_PROVIDER_NAME
        return provider

    async def fake_get_provider_match_mappings_for_provider_slugs(
        *,
        provider_slugs,
        target_date,
        timezone_name,
    ):
        assert target_date == date(2026, 4, 6)
        assert timezone_name == "Europe/Istanbul"
        assert HYBRID_LINEUP_PROVIDER_SLUG in provider_slugs
        return [
            (
                match_record,
                {
                    "sportsapipro-football-v2": "13500811",
                },
            )
        ]

    def fake_build_provider_client(provider_slug: str, *, settings, progress_callback=None):
        if provider_slug == "sportsapipro-football-v2":
            return MissingSportsApiClient()
        if provider_slug == "sofascore-football":
            return SofascoreClient()
        raise AssertionError(provider_slug)

    async def fake_persist_match_lineup(
        self,
        *,
        provider,
        sync_run,
        match,
        lineup,
        source_provider_slug=None,
        source_provider_match_id=None,
    ):
        assert provider.slug == HYBRID_LINEUP_PROVIDER_SLUG
        assert match.id == match_id
        assert lineup.provider_match_id == "13500811"
        assert source_provider_slug == "sofascore-football"
        assert source_provider_match_id == "13500811"
        self.player_service.stats.players_upserted = 1
        self.stats.appearances_upserted = 1
        self.stats.raw_payloads_written = 1
        return {}

    monkeypatch.setattr(service, "_get_or_create_provider", fake_get_or_create_provider)
    monkeypatch.setattr(
        service,
        "_get_provider_match_mappings_for_provider_slugs",
        fake_get_provider_match_mappings_for_provider_slugs,
    )
    monkeypatch.setattr(service, "_build_provider_client", fake_build_provider_client)
    monkeypatch.setattr(
        "app.services.match_lineup_persistence.MatchLineupPersistenceService.persist_match_lineup",
        fake_persist_match_lineup,
    )

    response = await service.trigger_provider_sync(
        provider_slug=HYBRID_LINEUP_PROVIDER_SLUG,
        scope="match-lineups",
        target_date=date(2026, 4, 6),
        timezone_name="Europe/Istanbul",
    )

    assert response.accepted is True
    assert response.status is not None
    assert response.status.value == "succeeded"
    assert response.stats is not None
    assert response.stats["matches_total"] == 1
    assert response.stats["matches_scanned"] == 1
    assert response.stats["matches_with_lineups"] == 1
    assert response.stats["matches_missing_lineups"] == 0
    assert response.stats["matches_failed"] == 0
    assert response.message == "Match lineup sync completed."


async def test_sync_service_hybrid_match_lineups_marks_missing_when_sources_missing(
    monkeypatch,
) -> None:
    from app.db.models.domain import Provider

    session = FakeSession()
    service = SyncService(session)

    provider = Provider(
        id=uuid.uuid4(),
        slug=HYBRID_LINEUP_PROVIDER_SLUG,
        name=HYBRID_LINEUP_PROVIDER_NAME,
        base_url=None,
        is_active=True,
        metadata_json={},
    )
    match_id = uuid.uuid4()
    match_record = SimpleNamespace(
        id=match_id,
        home_team=SimpleNamespace(id=uuid.uuid4(), name="Home FC"),
        away_team=SimpleNamespace(id=uuid.uuid4(), name="Away FC"),
        metadata_json={},
    )

    class MissingSportsApiClient:
        async def get_match_lineup(self, match_id: str):
            assert match_id == "15265728"
            return None

        async def aclose(self):
            return None

    class MissingSofascoreClient:
        async def get_match_lineup(self, match_id: str):
            assert match_id == "15898306"
            return None

        async def aclose(self):
            return None

    async def fake_get_or_create_provider(
        *,
        provider_slug: str,
        client,
        provider_name: str | None = None,
        base_url: str | None = None,
    ):
        assert provider_slug == HYBRID_LINEUP_PROVIDER_SLUG
        assert provider_name == HYBRID_LINEUP_PROVIDER_NAME
        return provider

    async def fake_get_provider_match_mappings_for_provider_slugs(
        *,
        provider_slugs,
        target_date,
        timezone_name,
    ):
        assert target_date == date(2026, 4, 6)
        assert timezone_name == "Europe/Istanbul"
        assert HYBRID_LINEUP_PROVIDER_SLUG in provider_slugs
        return [
            (
                match_record,
                {
                    "sportsapipro-football-v2": "15265728",
                    "sofascore-football": "15898306",
                },
            )
        ]

    def fake_build_provider_client(provider_slug: str, *, settings, progress_callback=None):
        if provider_slug == "sportsapipro-football-v2":
            return MissingSportsApiClient()
        if provider_slug == "sofascore-football":
            return MissingSofascoreClient()
        raise AssertionError(provider_slug)

    async def fake_persist_missing_match_lineup(
        self,
        *,
        provider,
        sync_run,
        match,
        provider_match_id,
        reason="no_lineup",
        source_provider_slug=None,
        source_provider_match_id=None,
    ):
        assert provider.slug == HYBRID_LINEUP_PROVIDER_SLUG
        assert match.id == match_id
        assert provider_match_id == "15898306"
        assert reason == "no_lineup"
        assert source_provider_slug == "sofascore-football"
        assert source_provider_match_id == "15898306"
        self.stats.matches_marked_no_lineup = 1
        return {}

    monkeypatch.setattr(service, "_get_or_create_provider", fake_get_or_create_provider)
    monkeypatch.setattr(
        service,
        "_get_provider_match_mappings_for_provider_slugs",
        fake_get_provider_match_mappings_for_provider_slugs,
    )
    monkeypatch.setattr(service, "_build_provider_client", fake_build_provider_client)
    monkeypatch.setattr(
        "app.services.match_lineup_persistence.MatchLineupPersistenceService.persist_missing_match_lineup",
        fake_persist_missing_match_lineup,
    )

    response = await service.trigger_provider_sync(
        provider_slug=HYBRID_LINEUP_PROVIDER_SLUG,
        scope="match-lineups",
        target_date=date(2026, 4, 6),
        timezone_name="Europe/Istanbul",
    )

    assert response.accepted is True
    assert response.status is not None
    assert response.status.value == "succeeded"
    assert response.stats is not None
    assert response.stats["matches_total"] == 1
    assert response.stats["matches_scanned"] == 1
    assert response.stats["matches_with_lineups"] == 0
    assert response.stats["matches_missing_lineups"] == 1
    assert response.stats["matches_failed"] == 0
    assert response.message == "Match lineup sync completed: skipped 1 missing lineups."


def test_map_match_status_keeps_not_started_scheduled() -> None:
    assert (
        MatchPersistenceService._map_match_status("notstarted", "Not started")
        == MatchStatus.scheduled
    )


def test_map_match_status_maps_started_to_live() -> None:
    assert MatchPersistenceService._map_match_status("started", "Started") == MatchStatus.live
