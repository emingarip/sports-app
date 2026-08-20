import enum
import uuid
from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.models.base import Base, MetadataMixin, TimestampMixin, UUIDPrimaryKeyMixin


class EntityType(str, enum.Enum):
    sport = "sport"
    category = "category"
    country = "country"
    competition = "competition"
    season = "season"
    competition_season = "competition_season"
    team = "team"
    player = "player"
    match = "match"


class CompetitionType(str, enum.Enum):
    league = "league"
    cup = "cup"
    international = "international"
    friendly = "friendly"
    other = "other"


class MatchStatus(str, enum.Enum):
    scheduled = "scheduled"
    live = "live"
    finished = "finished"
    postponed = "postponed"
    cancelled = "cancelled"
    unknown = "unknown"


class SyncRunStatus(str, enum.Enum):
    pending = "pending"
    running = "running"
    succeeded = "succeeded"
    failed = "failed"


class SnapshotPhase(str, enum.Enum):
    pre = "pre"
    live = "live"
    finalized = "finalized"


class RelationType(str, enum.Enum):
    country_has_competition = "country_has_competition"
    competition_has_season = "competition_has_season"
    team_participates_in_competition_season = "team_participates_in_competition_season"
    player_plays_for_team = "player_plays_for_team"
    match_belongs_to_competition_season = "match_belongs_to_competition_season"
    match_home_team = "match_home_team"
    match_away_team = "match_away_team"
    player_appeared_in_match = "player_appeared_in_match"


class Provider(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "providers"

    slug: Mapped[str] = mapped_column(String(50), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    base_url: Mapped[str | None] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    sync_runs: Mapped[list["SyncRun"]] = relationship(back_populates="provider")
    raw_payloads: Mapped[list["RawProviderPayload"]] = relationship(back_populates="provider")
    entity_mappings: Mapped[list["ProviderEntityMapping"]] = relationship(back_populates="provider")
    match_player_appearances: Mapped[list["MatchPlayerAppearance"]] = relationship(
        back_populates="provider"
    )


class Sport(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "sports"

    entity_uid: Mapped[str] = mapped_column(String(150), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(80), nullable=False)
    slug: Mapped[str] = mapped_column(String(80), unique=True, nullable=False)

    categories: Mapped[list["Category"]] = relationship(back_populates="sport")
    teams: Mapped[list["Team"]] = relationship(back_populates="sport")


class Country(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "countries"

    entity_uid: Mapped[str] = mapped_column(String(150), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(150), nullable=False)
    slug: Mapped[str] = mapped_column(String(150), unique=True, nullable=False)
    iso_code2: Mapped[str | None] = mapped_column(String(2))
    iso_code3: Mapped[str | None] = mapped_column(String(3))

    categories: Mapped[list["Category"]] = relationship(back_populates="country")
    competitions: Mapped[list["Competition"]] = relationship(back_populates="country")
    teams: Mapped[list["Team"]] = relationship(back_populates="country")
    players: Mapped[list["Player"]] = relationship(back_populates="country")


class Category(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "categories"

    entity_uid: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(150), nullable=False)
    slug: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    sport_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("sports.id"))
    country_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("countries.id"))
    priority: Mapped[int | None] = mapped_column(Integer)
    flag: Mapped[str | None] = mapped_column(String(80))

    sport: Mapped["Sport | None"] = relationship(back_populates="categories")
    country: Mapped["Country | None"] = relationship(back_populates="categories")
    competitions: Mapped[list["Competition"]] = relationship(back_populates="category")


class Competition(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "competitions"

    entity_uid: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(150), nullable=False)
    slug: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    competition_type: Mapped[CompetitionType] = mapped_column(
        Enum(CompetitionType, name="competition_type"),
        default=CompetitionType.league,
        nullable=False,
    )
    category_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("categories.id"))
    country_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("countries.id"))

    category: Mapped["Category | None"] = relationship(back_populates="competitions")
    country: Mapped["Country | None"] = relationship(back_populates="competitions")
    competition_seasons: Mapped[list["CompetitionSeason"]] = relationship(back_populates="competition")
    matches: Mapped[list["Match"]] = relationship(back_populates="competition")


class Season(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "seasons"

    entity_uid: Mapped[str] = mapped_column(String(150), unique=True, nullable=False)
    label: Mapped[str] = mapped_column(String(80), nullable=False)
    start_date: Mapped[date | None] = mapped_column(Date)
    end_date: Mapped[date | None] = mapped_column(Date)
    is_current: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    competition_seasons: Mapped[list["CompetitionSeason"]] = relationship(back_populates="season")
    matches: Mapped[list["Match"]] = relationship(back_populates="season")
    team_memberships: Mapped[list["TeamMembership"]] = relationship(back_populates="season")


class CompetitionSeason(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "competition_seasons"
    __table_args__ = (UniqueConstraint("competition_id", "season_id"),)

    entity_uid: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    competition_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("competitions.id"), nullable=False)
    season_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("seasons.id"), nullable=False)

    competition: Mapped["Competition"] = relationship(back_populates="competition_seasons")
    season: Mapped["Season"] = relationship(back_populates="competition_seasons")
    matches: Mapped[list["Match"]] = relationship(back_populates="competition_season")


class Team(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "teams"

    entity_uid: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(150), nullable=False)
    short_name: Mapped[str | None] = mapped_column(String(80))
    slug: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    sport_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("sports.id"))
    country_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("countries.id"))
    gender: Mapped[str | None] = mapped_column(String(24))
    is_national: Mapped[bool | None] = mapped_column(Boolean)
    team_type: Mapped[int | None] = mapped_column(Integer)

    sport: Mapped["Sport | None"] = relationship(back_populates="teams")
    country: Mapped["Country | None"] = relationship(back_populates="teams")
    aliases: Mapped[list["TeamAlias"]] = relationship(back_populates="team")
    player_memberships: Mapped[list["TeamMembership"]] = relationship(back_populates="team")
    home_matches: Mapped[list["Match"]] = relationship(
        back_populates="home_team",
        foreign_keys="Match.home_team_id",
    )
    away_matches: Mapped[list["Match"]] = relationship(
        back_populates="away_team",
        foreign_keys="Match.away_team_id",
    )
    match_appearances: Mapped[list["MatchPlayerAppearance"]] = relationship(
        back_populates="team"
    )


class TeamAlias(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "team_aliases"
    __table_args__ = (UniqueConstraint("team_id", "alias"),)

    team_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("teams.id"), nullable=False)
    alias: Mapped[str] = mapped_column(String(150), nullable=False)
    normalized_alias: Mapped[str] = mapped_column(String(180), nullable=False)
    provider_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("providers.id"))

    team: Mapped["Team"] = relationship(back_populates="aliases")


class Player(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "players"

    entity_uid: Mapped[str] = mapped_column(String(150), unique=True, nullable=False)
    full_name: Mapped[str] = mapped_column(String(180), nullable=False)
    short_name: Mapped[str | None] = mapped_column(String(120))
    slug: Mapped[str] = mapped_column(String(180), unique=True, nullable=False)
    date_of_birth: Mapped[date | None] = mapped_column(Date)
    country_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("countries.id"))

    country: Mapped["Country | None"] = relationship(back_populates="players")
    aliases: Mapped[list["PlayerAlias"]] = relationship(back_populates="player")
    team_memberships: Mapped[list["TeamMembership"]] = relationship(back_populates="player")
    match_appearances: Mapped[list["MatchPlayerAppearance"]] = relationship(
        back_populates="player"
    )


class PlayerAlias(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "player_aliases"
    __table_args__ = (UniqueConstraint("player_id", "alias"),)

    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id"), nullable=False)
    alias: Mapped[str] = mapped_column(String(180), nullable=False)
    normalized_alias: Mapped[str] = mapped_column(String(200), nullable=False)
    provider_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("providers.id"))

    player: Mapped["Player"] = relationship(back_populates="aliases")


class TeamMembership(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "team_memberships"
    __table_args__ = (UniqueConstraint("player_id", "team_id", "season_id"),)

    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id"), nullable=False)
    team_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("teams.id"), nullable=False)
    season_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("seasons.id"))
    squad_number: Mapped[int | None] = mapped_column(Integer)
    role: Mapped[str | None] = mapped_column(String(80))
    joined_on: Mapped[date | None] = mapped_column(Date)
    left_on: Mapped[date | None] = mapped_column(Date)
    is_current: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    player: Mapped["Player"] = relationship(back_populates="team_memberships")
    team: Mapped["Team"] = relationship(back_populates="player_memberships")
    season: Mapped["Season | None"] = relationship(back_populates="team_memberships")


class Match(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "matches"
    __table_args__ = (
        Index("ix_matches_kickoff_at_status", "kickoff_at", "status"),
        UniqueConstraint("entity_uid"),
    )

    entity_uid: Mapped[str] = mapped_column(String(255), nullable=False)
    competition_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("competitions.id"))
    season_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("seasons.id"))
    competition_season_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("competition_seasons.id")
    )
    home_team_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("teams.id"), nullable=False)
    away_team_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("teams.id"), nullable=False)
    kickoff_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    status: Mapped[MatchStatus] = mapped_column(
        Enum(MatchStatus, name="match_status"),
        default=MatchStatus.scheduled,
        nullable=False,
    )
    provider_status: Mapped[str | None] = mapped_column(String(80))
    venue_name: Mapped[str | None] = mapped_column(String(180))
    score_home: Mapped[int | None] = mapped_column(Integer)
    score_away: Mapped[int | None] = mapped_column(Integer)
    provider_last_synced_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    competition: Mapped["Competition | None"] = relationship(back_populates="matches")
    season: Mapped["Season | None"] = relationship(back_populates="matches")
    competition_season: Mapped["CompetitionSeason | None"] = relationship(back_populates="matches")
    home_team: Mapped["Team"] = relationship(
        back_populates="home_matches",
        foreign_keys=[home_team_id],
    )
    away_team: Mapped["Team"] = relationship(
        back_populates="away_matches",
        foreign_keys=[away_team_id],
    )
    player_appearances: Mapped[list["MatchPlayerAppearance"]] = relationship(
        back_populates="match"
    )


class MatchPlayerAppearance(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "match_player_appearances"
    __table_args__ = (
        UniqueConstraint("provider_id", "match_id", "player_id"),
        Index("ix_match_player_appearances_provider_match_side", "provider_id", "match_id", "side"),
    )

    provider_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("providers.id"), nullable=False)
    match_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("matches.id"), nullable=False)
    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id"), nullable=False)
    team_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("teams.id"), nullable=False)
    side: Mapped[str] = mapped_column(String(8), nullable=False)
    is_starter: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_substitute: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    played: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    minutes_played: Mapped[int | None] = mapped_column(Integer)
    position: Mapped[str | None] = mapped_column(String(32))
    squad_number: Mapped[int | None] = mapped_column(Integer)

    provider: Mapped["Provider"] = relationship(back_populates="match_player_appearances")
    match: Mapped["Match"] = relationship(back_populates="player_appearances")
    player: Mapped["Player"] = relationship(back_populates="match_appearances")
    team: Mapped["Team"] = relationship(back_populates="match_appearances")


class MatchEventTimeline(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "match_event_timeline"
    __table_args__ = (
        UniqueConstraint("provider_id", "match_id", "provider_event_id"),
        Index("ix_match_event_timeline_match_minute", "match_id", "minute", "sort_order"),
    )

    provider_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("providers.id"), nullable=False)
    match_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("matches.id"), nullable=False)
    provider_event_id: Mapped[str] = mapped_column(String(180), nullable=False)
    event_type: Mapped[str] = mapped_column(String(64), nullable=False)
    event_subtype: Mapped[str | None] = mapped_column(String(64))
    team_side: Mapped[str | None] = mapped_column(String(8))
    minute: Mapped[int | None] = mapped_column(Integer)
    stoppage_minute: Mapped[int | None] = mapped_column(Integer)
    sort_order: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    player_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("players.id"))
    related_player_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("players.id"))
    player_name: Mapped[str | None] = mapped_column(String(180))
    related_player_name: Mapped[str | None] = mapped_column(String(180))
    score_home: Mapped[int | None] = mapped_column(Integer)
    score_away: Mapped[int | None] = mapped_column(Integer)
    occurred_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class MatchMarketTick(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "match_market_ticks"
    __table_args__ = (
        UniqueConstraint(
            "provider_id",
            "match_id",
            "snapshot_phase",
            "market_type",
            "selection_key",
            "line_value",
            "tick_time",
        ),
        Index("ix_match_market_ticks_match_time", "match_id", "tick_time"),
    )

    provider_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("providers.id"), nullable=False)
    match_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("matches.id"), nullable=False)
    snapshot_phase: Mapped[SnapshotPhase] = mapped_column(
        Enum(SnapshotPhase, name="snapshot_phase"),
        nullable=False,
    )
    market_type: Mapped[str] = mapped_column(String(64), nullable=False)
    selection_key: Mapped[str] = mapped_column(String(64), nullable=False)
    tick_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    minute: Mapped[int | None] = mapped_column(Integer)
    line_value: Mapped[float | None] = mapped_column(Float)
    odds_decimal: Mapped[float | None] = mapped_column(Float)
    implied_prob: Mapped[float | None] = mapped_column(Float)
    normalized_prob: Mapped[float | None] = mapped_column(Float)
    bookmaker_key: Mapped[str | None] = mapped_column(String(80))
    suspended: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)


class MatchLiveStatFrame(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "match_live_stat_frames"
    __table_args__ = (
        UniqueConstraint("provider_id", "match_id", "minute", "tick_time"),
        Index("ix_match_live_stat_frames_match_time", "match_id", "tick_time"),
    )

    provider_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("providers.id"), nullable=False)
    match_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("matches.id"), nullable=False)
    tick_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    minute: Mapped[int | None] = mapped_column(Integer)
    home_xg: Mapped[float | None] = mapped_column(Float)
    away_xg: Mapped[float | None] = mapped_column(Float)
    home_shots: Mapped[int | None] = mapped_column(Integer)
    away_shots: Mapped[int | None] = mapped_column(Integer)
    home_shots_on_target: Mapped[int | None] = mapped_column(Integer)
    away_shots_on_target: Mapped[int | None] = mapped_column(Integer)
    home_corners: Mapped[int | None] = mapped_column(Integer)
    away_corners: Mapped[int | None] = mapped_column(Integer)
    home_possession: Mapped[float | None] = mapped_column(Float)
    away_possession: Mapped[float | None] = mapped_column(Float)
    home_dangerous_attacks: Mapped[int | None] = mapped_column(Integer)
    away_dangerous_attacks: Mapped[int | None] = mapped_column(Integer)
    home_box_entries: Mapped[int | None] = mapped_column(Integer)
    away_box_entries: Mapped[int | None] = mapped_column(Integer)
    home_pressure_index: Mapped[float | None] = mapped_column(Float)
    away_pressure_index: Mapped[float | None] = mapped_column(Float)


class TeamRatingDaily(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "team_rating_daily"
    __table_args__ = (
        UniqueConstraint("team_id", "rating_date", "feature_version"),
        Index("ix_team_rating_daily_date", "rating_date"),
    )

    team_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("teams.id"), nullable=False)
    competition_season_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("competition_seasons.id")
    )
    rating_date: Mapped[date] = mapped_column(Date, nullable=False)
    feature_version: Mapped[str] = mapped_column(String(32), nullable=False)
    elo_rating: Mapped[float | None] = mapped_column(Float)
    team_strength: Mapped[float | None] = mapped_column(Float)
    form_points_avg: Mapped[float | None] = mapped_column(Float)
    xg_form_avg: Mapped[float | None] = mapped_column(Float)
    xga_form_avg: Mapped[float | None] = mapped_column(Float)
    rest_days: Mapped[float | None] = mapped_column(Float)
    fatigue_minutes_14d: Mapped[int | None] = mapped_column(Integer)
    matches_sampled: Mapped[int | None] = mapped_column(Integer)
    availability_json: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)
    quality_json: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)
    source_json: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)


class PlayerRatingDaily(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "player_rating_daily"
    __table_args__ = (
        UniqueConstraint("player_id", "rating_date", "feature_version"),
        Index("ix_player_rating_daily_date", "rating_date"),
    )

    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id"), nullable=False)
    team_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("teams.id"))
    rating_date: Mapped[date] = mapped_column(Date, nullable=False)
    feature_version: Mapped[str] = mapped_column(String(32), nullable=False)
    player_power: Mapped[float | None] = mapped_column(Float)
    appearance_rating: Mapped[float | None] = mapped_column(Float)
    recent_minutes: Mapped[int | None] = mapped_column(Integer)
    appearances_sampled: Mapped[int | None] = mapped_column(Integer)
    role_code: Mapped[str | None] = mapped_column(String(32))
    availability_json: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)
    quality_json: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)
    source_json: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)


class MatchFeatureSnapshot(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "match_feature_snapshots"
    __table_args__ = (
        UniqueConstraint("match_id", "snapshot_phase", "snapshot_minute", "feature_version"),
        Index("ix_match_feature_snapshots_match_phase_minute", "match_id", "snapshot_phase", "snapshot_minute"),
    )

    match_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("matches.id"), nullable=False)
    snapshot_phase: Mapped[SnapshotPhase] = mapped_column(
        Enum(SnapshotPhase, name="match_feature_snapshot_phase"),
        nullable=False,
    )
    snapshot_minute: Mapped[int] = mapped_column(Integer, nullable=False)
    snapshot_ts: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    feature_version: Mapped[str] = mapped_column(String(32), nullable=False)
    is_finalized: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    availability_json: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)
    quality_json: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)
    source_json: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)
    expected_goal_line_proxy: Mapped[bool | None] = mapped_column(Boolean)
    predicted_lineup_low_history: Mapped[bool | None] = mapped_column(Boolean)
    betfair_unavailable: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    state_model_home_prob: Mapped[float | None] = mapped_column(Float)
    pre_home_prob: Mapped[float | None] = mapped_column(Float)
    pre_draw_prob: Mapped[float | None] = mapped_column(Float)
    pre_away_prob: Mapped[float | None] = mapped_column(Float)
    pre_favorite_gap: Mapped[float | None] = mapped_column(Float)
    pre_expected_goal_line: Mapped[float | None] = mapped_column(Float)
    team_strength_diff: Mapped[float | None] = mapped_column(Float)
    elo_diff: Mapped[float | None] = mapped_column(Float)
    form_points_diff: Mapped[float | None] = mapped_column(Float)
    xg_form_diff: Mapped[float | None] = mapped_column(Float)
    xga_form_diff: Mapped[float | None] = mapped_column(Float)
    rest_days_diff: Mapped[float | None] = mapped_column(Float)
    fatigue_diff: Mapped[float | None] = mapped_column(Float)
    pred_home_lineup_strength: Mapped[float | None] = mapped_column(Float)
    pred_away_lineup_strength: Mapped[float | None] = mapped_column(Float)
    pred_lineup_strength_diff: Mapped[float | None] = mapped_column(Float)
    real_home_lineup_strength: Mapped[float | None] = mapped_column(Float)
    real_away_lineup_strength: Mapped[float | None] = mapped_column(Float)
    real_lineup_strength_diff: Mapped[float | None] = mapped_column(Float)
    home_defense_strength: Mapped[float | None] = mapped_column(Float)
    away_defense_strength: Mapped[float | None] = mapped_column(Float)
    midfield_strength_diff: Mapped[float | None] = mapped_column(Float)
    attack_strength_diff: Mapped[float | None] = mapped_column(Float)
    lineup_surprise_score: Mapped[float | None] = mapped_column(Float)
    rotation_diff: Mapped[float | None] = mapped_column(Float)
    missing_strength_diff: Mapped[float | None] = mapped_column(Float)
    minute_norm: Mapped[float | None] = mapped_column(Float)
    time_remaining_norm: Mapped[float | None] = mapped_column(Float)
    home_score: Mapped[int | None] = mapped_column(Integer)
    away_score: Mapped[int | None] = mapped_column(Integer)
    score_diff: Mapped[int | None] = mapped_column(Integer)
    goal_total: Mapped[int | None] = mapped_column(Integer)
    home_red_cards: Mapped[int | None] = mapped_column(Integer)
    away_red_cards: Mapped[int | None] = mapped_column(Integer)
    red_card_diff: Mapped[int | None] = mapped_column(Integer)
    yellow_card_diff: Mapped[int | None] = mapped_column(Integer)
    subs_diff: Mapped[int | None] = mapped_column(Integer)
    time_since_last_goal: Mapped[float | None] = mapped_column(Float)
    time_since_last_red_card: Mapped[float | None] = mapped_column(Float)
    xg_diff_total: Mapped[float | None] = mapped_column(Float)
    shots_diff_total: Mapped[float | None] = mapped_column(Float)
    sot_diff_total: Mapped[float | None] = mapped_column(Float)
    corners_diff_total: Mapped[float | None] = mapped_column(Float)
    possession_diff: Mapped[float | None] = mapped_column(Float)
    xg_diff_last5: Mapped[float | None] = mapped_column(Float)
    xg_diff_last10: Mapped[float | None] = mapped_column(Float)
    shots_diff_last5: Mapped[float | None] = mapped_column(Float)
    shots_diff_last10: Mapped[float | None] = mapped_column(Float)
    sot_diff_last10: Mapped[float | None] = mapped_column(Float)
    dangerous_attacks_diff_last10: Mapped[float | None] = mapped_column(Float)
    box_entries_diff_last10: Mapped[float | None] = mapped_column(Float)
    pressure_diff_last10: Mapped[float | None] = mapped_column(Float)
    momentum_diff: Mapped[float | None] = mapped_column(Float)
    live_home_prob: Mapped[float | None] = mapped_column(Float)
    live_draw_prob: Mapped[float | None] = mapped_column(Float)
    live_away_prob: Mapped[float | None] = mapped_column(Float)
    live_over25_prob: Mapped[float | None] = mapped_column(Float)
    live_under25_prob: Mapped[float | None] = mapped_column(Float)
    live_next_goal_home_prob: Mapped[float | None] = mapped_column(Float)
    home_prob_shift_from_pre: Mapped[float | None] = mapped_column(Float)
    draw_prob_shift_from_pre: Mapped[float | None] = mapped_column(Float)
    away_prob_shift_from_pre: Mapped[float | None] = mapped_column(Float)
    home_prob_change_last1: Mapped[float | None] = mapped_column(Float)
    home_prob_change_last5: Mapped[float | None] = mapped_column(Float)
    market_volatility_last5: Mapped[float | None] = mapped_column(Float)
    betfair_total_matched: Mapped[float | None] = mapped_column(Float)
    betfair_liquidity_score: Mapped[float | None] = mapped_column(Float)
    betfair_home_spread: Mapped[float | None] = mapped_column(Float)
    market_overreaction_score: Mapped[float | None] = mapped_column(Float)
    market_underreaction_score: Mapped[float | None] = mapped_column(Float)
    favorite_fragility_score: Mapped[float | None] = mapped_column(Float)
    underdog_resistance_score: Mapped[float | None] = mapped_column(Float)
    comeback_potential_score: Mapped[float | None] = mapped_column(Float)
    late_goal_risk_score: Mapped[float | None] = mapped_column(Float)
    state_cluster_id: Mapped[int | None] = mapped_column(Integer)
    score_state_class: Mapped[str | None] = mapped_column(String(64))
    market_state_class: Mapped[str | None] = mapped_column(String(64))
    label_final_result_1x2: Mapped[str | None] = mapped_column(String(8))
    label_home_win: Mapped[bool | None] = mapped_column(Boolean)
    label_goal_next10min: Mapped[bool | None] = mapped_column(Boolean)
    label_next_goal_team: Mapped[str | None] = mapped_column(String(16))
    label_result_from_snapshot_to_end: Mapped[str | None] = mapped_column(String(16))
    label_over25_from_snapshot: Mapped[bool | None] = mapped_column(Boolean)


class MatchPrediction(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    """Model-generated market probabilities and value picks for one match."""

    __tablename__ = "match_predictions"
    __table_args__ = (
        UniqueConstraint("match_id", "model_version", "phase"),
        Index("ix_match_predictions_generated_at", "generated_at"),
    )

    match_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("matches.id"), nullable=False)
    model_version: Mapped[str] = mapped_column(String(64), nullable=False)
    phase: Mapped[SnapshotPhase] = mapped_column(
        Enum(SnapshotPhase, name="snapshot_phase"),
        default=SnapshotPhase.pre,
        nullable=False,
    )
    generated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    lambda_home: Mapped[float | None] = mapped_column(Float)
    lambda_away: Mapped[float | None] = mapped_column(Float)
    rho: Mapped[float | None] = mapped_column(Float)
    market_probs: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)
    value_picks: Mapped[list] = mapped_column(JSONB, default=list, nullable=False)

    match: Mapped["Match"] = relationship()


class ProviderEntityMapping(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "provider_entity_mappings"
    __table_args__ = (UniqueConstraint("provider_id", "entity_type", "provider_entity_id"),)

    provider_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("providers.id"), nullable=False)
    entity_type: Mapped[EntityType] = mapped_column(
        Enum(EntityType, name="entity_type"),
        nullable=False,
    )
    provider_entity_id: Mapped[str] = mapped_column(String(180), nullable=False)
    canonical_entity_uid: Mapped[str] = mapped_column(String(255), nullable=False)

    provider: Mapped["Provider"] = relationship(back_populates="entity_mappings")


class SyncRun(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "sync_runs"

    provider_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("providers.id"), nullable=False)
    scope: Mapped[str] = mapped_column(String(80), nullable=False)
    target_date: Mapped[date | None] = mapped_column(Date)
    status: Mapped[SyncRunStatus] = mapped_column(
        Enum(SyncRunStatus, name="sync_run_status"),
        default=SyncRunStatus.pending,
        nullable=False,
    )
    stats: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)
    error_message: Mapped[str | None] = mapped_column(Text)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    provider: Mapped["Provider"] = relationship(back_populates="sync_runs")
    raw_payloads: Mapped[list["RawProviderPayload"]] = relationship(back_populates="sync_run")


class RawProviderPayload(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "raw_provider_payloads"
    __table_args__ = (
        UniqueConstraint("provider_id", "entity_type", "provider_entity_id", "checksum"),
    )

    provider_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("providers.id"), nullable=False)
    sync_run_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("sync_runs.id"))
    entity_type: Mapped[EntityType] = mapped_column(
        Enum(EntityType, name="raw_payload_entity_type"),
        nullable=False,
    )
    provider_entity_id: Mapped[str] = mapped_column(String(180), nullable=False)
    checksum: Mapped[str] = mapped_column(String(64), nullable=False)
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False)
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    provider: Mapped["Provider"] = relationship(back_populates="raw_payloads")
    sync_run: Mapped["SyncRun | None"] = relationship(back_populates="raw_payloads")


class EntityRelation(UUIDPrimaryKeyMixin, TimestampMixin, MetadataMixin, Base):
    __tablename__ = "entity_relations"
    __table_args__ = (
        UniqueConstraint("source_entity_uid", "target_entity_uid", "relation_type"),
        Index("ix_entity_relations_source", "source_entity_uid"),
        Index("ix_entity_relations_target", "target_entity_uid"),
    )

    source_entity_uid: Mapped[str] = mapped_column(String(255), nullable=False)
    target_entity_uid: Mapped[str] = mapped_column(String(255), nullable=False)
    relation_type: Mapped[RelationType] = mapped_column(
        Enum(RelationType, name="relation_type"),
        nullable=False,
    )
    weight: Mapped[float] = mapped_column(Float, default=1.0, nullable=False)
