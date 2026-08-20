from app.providers.registry import REGISTERED_PROVIDER_CLIENTS
from app.providers.sportsapipro_football_v1 import SportsAPIProFootballV1Client
from app.providers.sportsapipro_football_v2 import SportsAPIProFootballV2Client


def test_registry_contains_sportsapipro_v1_client() -> None:
    assert REGISTERED_PROVIDER_CLIENTS[SportsAPIProFootballV1Client.slug] is SportsAPIProFootballV1Client


def test_registry_contains_sportsapipro_client() -> None:
    assert REGISTERED_PROVIDER_CLIENTS[SportsAPIProFootballV2Client.slug] is SportsAPIProFootballV2Client
