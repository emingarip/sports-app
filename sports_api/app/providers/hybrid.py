from __future__ import annotations

from app.providers.sofascore_football import SofascoreFootballClient
from app.providers.sportsapipro_football_v2 import SportsAPIProFootballV2Client

HYBRID_LINEUP_PROVIDER_SLUG = "sportsapipro-then-sofascore"
HYBRID_LINEUP_PROVIDER_NAME = "SportsAPI Pro -> Sofascore (Hybrid)"

HYBRID_LINEUP_SOURCE_PROVIDER_SLUGS: tuple[str, str] = (
    SportsAPIProFootballV2Client.slug,
    SofascoreFootballClient.slug,
)


def is_hybrid_lineup_provider(provider_slug: str | None) -> bool:
    return provider_slug == HYBRID_LINEUP_PROVIDER_SLUG


def expand_lineup_provider_slugs(provider_slug: str) -> tuple[str, ...]:
    if is_hybrid_lineup_provider(provider_slug):
        return (
            HYBRID_LINEUP_PROVIDER_SLUG,
            *HYBRID_LINEUP_SOURCE_PROVIDER_SLUGS,
        )
    return (provider_slug,)
