from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import date, datetime

from app.core.config import Settings, get_settings


@dataclass(slots=True)
class ProviderBatch:
    scope: str
    target_date: date | None
    entities: list[dict] = field(default_factory=list)
    matches: list["ProviderMatchSeed"] = field(default_factory=list)


@dataclass(slots=True)
class ProviderSportSeed:
    provider_sport_id: str | None
    name: str
    slug: str | None = None
    raw: dict = field(default_factory=dict)


@dataclass(slots=True)
class ProviderCountrySeed:
    provider_country_id: str | None
    name: str
    slug: str | None = None
    iso_code2: str | None = None
    iso_code3: str | None = None
    raw: dict = field(default_factory=dict)


@dataclass(slots=True)
class BootstrapCategorySeed:
    provider_category_id: str
    name: str
    slug: str | None = None
    sport: ProviderSportSeed | None = None
    country: ProviderCountrySeed | None = None
    priority: int | None = None
    flag: str | None = None
    parent_provider_category_id: str | None = None
    raw: dict = field(default_factory=dict)


@dataclass(slots=True)
class BootstrapTournamentSeed:
    provider_tournament_id: str
    name: str
    slug: str | None = None
    category_provider_id: str | None = None
    category: BootstrapCategorySeed | None = None
    raw: dict = field(default_factory=dict)


@dataclass(slots=True)
class BootstrapSeasonSeed:
    provider_season_id: str
    tournament_provider_id: str
    name: str
    year: str | None = None
    is_current: bool | None = None
    raw: dict = field(default_factory=dict)


@dataclass(slots=True)
class ProviderBootstrapCatalog:
    categories: list[BootstrapCategorySeed] = field(default_factory=list)
    tournaments: list[BootstrapTournamentSeed] = field(default_factory=list)
    seasons: list[BootstrapSeasonSeed] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    def to_stats(self) -> dict[str, int]:
        return {
            "categories_count": len(self.categories),
            "tournaments_count": len(self.tournaments),
            "seasons_count": len(self.seasons),
            "errors_count": len(self.errors),
        }


@dataclass(slots=True)
class ProviderTeamSeed:
    provider_team_id: str
    name: str
    slug: str | None = None
    short_name: str | None = None
    sport: ProviderSportSeed | None = None
    country: ProviderCountrySeed | None = None
    gender: str | None = None
    national: bool | None = None
    team_type: int | None = None
    raw: dict = field(default_factory=dict)


@dataclass(slots=True)
class ProviderMatchSeed:
    provider_match_id: str
    kickoff_at: datetime
    status: str
    provider_status: str | None
    home_team: ProviderTeamSeed
    away_team: ProviderTeamSeed
    competition: BootstrapTournamentSeed | None = None
    season: BootstrapSeasonSeed | None = None
    venue_name: str | None = None
    score_home: int | None = None
    score_away: int | None = None
    score_home_ht: int | None = None
    score_away_ht: int | None = None
    raw: dict = field(default_factory=dict)


@dataclass(slots=True)
class ProviderPlayerSeed:
    provider_player_id: str
    full_name: str
    short_name: str | None = None
    slug: str | None = None
    date_of_birth: date | None = None
    country: ProviderCountrySeed | None = None
    team_provider_id: str | None = None
    squad_number: int | None = None
    role: str | None = None
    is_current: bool | None = None
    raw: dict = field(default_factory=dict)


@dataclass(slots=True)
class ProviderMatchLineupEntrySeed:
    player: ProviderPlayerSeed
    team_side: str
    is_starter: bool
    is_substitute: bool
    played: bool
    minutes_played: int | None = None
    position: str | None = None
    squad_number: int | None = None
    statistics: dict = field(default_factory=dict)
    raw: dict = field(default_factory=dict)


@dataclass(slots=True)
class ProviderMatchLineupSeed:
    provider_match_id: str
    confirmed: bool | None = None
    home_formation: str | None = None
    away_formation: str | None = None
    home_players: list[ProviderMatchLineupEntrySeed] = field(default_factory=list)
    away_players: list[ProviderMatchLineupEntrySeed] = field(default_factory=list)
    raw: dict = field(default_factory=dict)


@dataclass(slots=True)
class ProviderMatchMarketTickSeed:
    provider_match_id: str
    phase: str
    market_type: str
    selection_key: str
    tick_time: datetime | None = None
    minute: int | None = None
    line_value: float | None = None
    odds_decimal: float | None = None
    implied_prob: float | None = None
    normalized_prob: float | None = None
    bookmaker_key: str | None = None
    suspended: bool | None = None
    raw: dict = field(default_factory=dict)


@dataclass(slots=True)
class ProviderMatchIncidentSeed:
    provider_match_id: str
    provider_event_id: str
    incident_type: str
    incident_subtype: str | None = None
    team_side: str | None = None
    minute: int | None = None
    stoppage_minute: int | None = None
    sort_order: int = 0
    player_provider_id: str | None = None
    related_player_provider_id: str | None = None
    player_name: str | None = None
    related_player_name: str | None = None
    score_home: int | None = None
    score_away: int | None = None
    score_home_ht: int | None = None
    score_away_ht: int | None = None
    occurred_at: datetime | None = None
    raw: dict = field(default_factory=dict)


@dataclass(slots=True)
class ProviderShotEventSeed:
    provider_match_id: str
    provider_shot_id: str
    team_side: str | None = None
    minute: int | None = None
    second: int | None = None
    xg: float | None = None
    xgot: float | None = None
    on_target: bool | None = None
    resulted_in_goal: bool | None = None
    raw: dict = field(default_factory=dict)


@dataclass(slots=True)
class ProviderMatchLiveStatFrameSeed:
    provider_match_id: str
    frame_time: datetime | None = None
    minute: int | None = None
    home_xg: float | None = None
    away_xg: float | None = None
    home_shots: int | None = None
    away_shots: int | None = None
    home_shots_on_target: int | None = None
    away_shots_on_target: int | None = None
    home_corners: int | None = None
    away_corners: int | None = None
    home_possession: float | None = None
    away_possession: float | None = None
    home_dangerous_attacks: int | None = None
    away_dangerous_attacks: int | None = None
    home_box_entries: int | None = None
    away_box_entries: int | None = None
    home_pressure_index: float | None = None
    away_pressure_index: float | None = None
    raw: dict = field(default_factory=dict)


class ProviderClient(ABC):
    slug: str
    display_name: str

    def __init__(self, *, settings: Settings | None = None) -> None:
        self.settings = settings or get_settings()

    @abstractmethod
    async def fetch(self, *, scope: str, target_date: date | None) -> ProviderBatch:
        """Fetch raw provider payloads for a given scope."""

    async def bootstrap_catalog(self) -> ProviderBootstrapCatalog:
        raise NotImplementedError("This provider does not implement bootstrap discovery.")

    async def aclose(self) -> None:  # noqa: B027 - deliberate no-op default
        """Release any provider-specific resources.

        Intentionally concrete and empty: most providers hold nothing to
        release, and forcing every subclass to write an empty override
        would be noise.
        """

    async def get_team_players(self, team_provider_id: str) -> list[ProviderPlayerSeed]:
        raise NotImplementedError("This provider does not implement team player discovery.")

    async def get_match_lineup(self, match_id: str) -> ProviderMatchLineupSeed | None:
        raise NotImplementedError("This provider does not implement match lineup discovery.")

    async def get_prematch_markets(
        self,
        match_id: str,
    ) -> list[ProviderMatchMarketTickSeed]:
        raise NotImplementedError("This provider does not implement prematch markets.")

    async def get_live_markets(
        self,
        match_id: str,
    ) -> list[ProviderMatchMarketTickSeed]:
        raise NotImplementedError("This provider does not implement live markets.")

    async def get_match_incidents(
        self,
        match_id: str,
    ) -> list[ProviderMatchIncidentSeed]:
        raise NotImplementedError("This provider does not implement match incidents.")

    async def get_match_live_stats(
        self,
        match_id: str,
    ) -> list[ProviderMatchLiveStatFrameSeed]:
        raise NotImplementedError("This provider does not implement live stats.")

    async def get_match_shotmap(
        self,
        match_id: str,
    ) -> list[ProviderShotEventSeed]:
        raise NotImplementedError("This provider does not implement shotmap discovery.")
