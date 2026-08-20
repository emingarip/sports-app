from app.providers.base import ProviderClient
from app.providers.iddaa_bulletin import IddaaBulletinClient
from app.providers.sofascore_football import SofascoreFootballClient
from app.providers.sportsapipro_football_v1 import SportsAPIProFootballV1Client
from app.providers.sportsapipro_football_v2 import SportsAPIProFootballV2Client

REGISTERED_PROVIDER_CLIENTS: dict[str, type[ProviderClient]] = {
    IddaaBulletinClient.slug: IddaaBulletinClient,
    SofascoreFootballClient.slug: SofascoreFootballClient,
    SportsAPIProFootballV1Client.slug: SportsAPIProFootballV1Client,
    SportsAPIProFootballV2Client.slug: SportsAPIProFootballV2Client,
}
