from datetime import UTC, datetime
from types import SimpleNamespace

from app.providers.base import (
    BootstrapSeasonSeed,
    BootstrapTournamentSeed,
    ProviderMatchSeed,
    ProviderTeamSeed,
)
from app.services.bootstrap_persistence import BootstrapPersistenceService
from app.services.match_persistence import MatchPersistenceService


def test_normalize_season_label_uses_match_kickoff_for_single_year() -> None:
    seed = BootstrapSeasonSeed(
        provider_season_id="500",
        tournament_provider_id="100",
        name="2026",
        year="2026",
    )

    label = BootstrapPersistenceService._normalize_season_label(
        seed,
        kickoff_at=datetime(2026, 3, 31, 15, 0, tzinfo=UTC),
    )

    assert label == "25/26"


async def test_match_persistence_passes_kickoff_to_season_upsert(monkeypatch) -> None:
    service = MatchPersistenceService(session=object())
    provider = SimpleNamespace(slug="fake-provider")
    captured: dict[str, datetime | None] = {"kickoff_at": None}

    competition = SimpleNamespace(id="competition-1")
    season = SimpleNamespace(id="season-1", entity_uid="season:25-26")
    competition_season = SimpleNamespace(id="competition-season-1")
    home_team = SimpleNamespace(id="team-home")
    away_team = SimpleNamespace(id="team-away")
    match = SimpleNamespace(home_team=None, away_team=None, competition_season=None)

    async def fake_upsert_competition_seed(**_kwargs):
        return competition

    async def fake_upsert_season_seed(**kwargs):
        captured["kickoff_at"] = kwargs.get("kickoff_at")
        return season

    async def fake_upsert_competition_season_seed(**_kwargs):
        return competition_season

    async def fake_none(**_kwargs):
        return None

    async def fake_team(*, seed, **_kwargs):
        return home_team if seed.provider_team_id == "1" else away_team

    async def fake_match(**_kwargs):
        return match

    monkeypatch.setattr(service.catalog, "upsert_competition_seed", fake_upsert_competition_seed)
    monkeypatch.setattr(service.catalog, "upsert_season_seed", fake_upsert_season_seed)
    monkeypatch.setattr(
        service.catalog,
        "upsert_competition_season_seed",
        fake_upsert_competition_season_seed,
    )
    monkeypatch.setattr(service, "_upsert_country_from_team_seed", fake_none)
    monkeypatch.setattr(service, "_upsert_sport_from_team_seed", fake_none)
    monkeypatch.setattr(service, "_upsert_team", fake_team)
    monkeypatch.setattr(service, "_upsert_match", fake_match)
    monkeypatch.setattr("app.services.match_persistence.build_match_relation_drafts", lambda _match: [])

    seed = ProviderMatchSeed(
        provider_match_id="14025056",
        kickoff_at=datetime(2026, 3, 31, 15, 0, tzinfo=UTC),
        status="finished",
        provider_status="Ended",
        home_team=ProviderTeamSeed(provider_team_id="1", name="Finland U21"),
        away_team=ProviderTeamSeed(provider_team_id="2", name="Cyprus U21"),
        competition=BootstrapTournamentSeed(
            provider_tournament_id="100",
            name="UEFA U21 Championship Qualification",
        ),
        season=BootstrapSeasonSeed(
            provider_season_id="500",
            tournament_provider_id="100",
            name="2026",
            year="2026",
        ),
        raw={},
    )

    await service._persist_match_seed(provider=provider, sync_run=None, seed=seed)

    assert captured["kickoff_at"] == seed.kickoff_at
