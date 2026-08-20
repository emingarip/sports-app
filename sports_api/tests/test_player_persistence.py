from datetime import date
from types import SimpleNamespace

from app.providers.base import ProviderPlayerSeed
from app.services.player_persistence import PlayerPersistenceService


class DummySession:
    pass


async def test_player_slug_resolution_falls_back_when_base_slug_collides(monkeypatch) -> None:
    service = PlayerPersistenceService(DummySession())
    seed = ProviderPlayerSeed(
        provider_player_id="2510362",
        full_name="Javier Garcia",
        short_name="J. Garcia",
        slug="javier-garcia",
        date_of_birth=date(1998, 3, 23),
    )
    country = SimpleNamespace(slug="usa")
    entity_uid = "player:usa:javier-garcia-1998-03-23:1998-03-23"

    async def fake_find_player_by_slug(slug: str):
        if slug == "javier-garcia-1998-03-23":
            return SimpleNamespace(entity_uid="player:mex:javier-garcia-1998-03-23:1998-03-23")
        return None

    monkeypatch.setattr(service, "_find_player_by_slug", fake_find_player_by_slug)

    slug = await service._resolve_unique_player_slug(
        seed=seed,
        country=country,
        entity_uid=entity_uid,
    )

    assert slug == "usa-javier-garcia-1998-03-23"


async def test_player_slug_resolution_keeps_base_slug_for_same_entity(monkeypatch) -> None:
    service = PlayerPersistenceService(DummySession())
    seed = ProviderPlayerSeed(
        provider_player_id="2510362",
        full_name="Javier Garcia",
        short_name="J. Garcia",
        slug="javier-garcia",
        date_of_birth=date(1998, 3, 23),
    )
    entity_uid = "player:usa:javier-garcia-1998-03-23:1998-03-23"

    async def fake_find_player_by_slug(slug: str):
        if slug == "javier-garcia-1998-03-23":
            return SimpleNamespace(entity_uid=entity_uid)
        return None

    monkeypatch.setattr(service, "_find_player_by_slug", fake_find_player_by_slug)

    slug = await service._resolve_unique_player_slug(
        seed=seed,
        country=SimpleNamespace(slug="usa"),
        entity_uid=entity_uid,
    )

    assert slug == "javier-garcia-1998-03-23"
