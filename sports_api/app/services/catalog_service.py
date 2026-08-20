from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from uuid import UUID

from sqlalchemy import Select, case, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.timezones import utc_day_bounds
from app.db.models.domain import (
    Competition,
    CompetitionSeason,
    Country,
    EntityType,
    Match,
    MatchPlayerAppearance,
    MatchStatus,
    Player,
    Provider,
    ProviderEntityMapping,
    RawProviderPayload,
    Season,
    SyncRun,
    Team,
    TeamMembership,
)
from app.providers.hybrid import expand_lineup_provider_slugs
from app.schemas.catalog import (
    CatalogOverview,
    CompetitionSummary,
    CountrySummary,
    SeasonSummary,
    SyncRunSummary,
)


@dataclass(slots=True)
class CatalogDashboardSnapshot:
    counts: dict[str, int]
    providers: list[Provider]
    sync_runs: list[SyncRun]
    countries: list[Country]
    competitions: list[Competition]
    seasons: list[Season]
    competition_seasons: list[CompetitionSeason]
    matches: list[Match]


async def build_catalog_dashboard_snapshot(
    session: AsyncSession,
) -> CatalogDashboardSnapshot:
    counts = {
        "providers": await _count_rows(session, Provider),
        "countries": await _count_rows(session, Country),
        "competitions": await _count_rows(session, Competition),
        "seasons": await _count_rows(session, Season),
        "competition_seasons": await _count_rows(session, CompetitionSeason),
        "teams": await _count_rows(session, Team),
        "players": await _count_rows(session, Player),
        "matches": await _count_rows(session, Match),
        "mappings": await _count_rows(session, ProviderEntityMapping),
        "raw_payloads": await _count_rows(session, RawProviderPayload),
        "sync_runs": await _count_rows(session, SyncRun),
    }

    providers = await _fetch_rows(
        session,
        select(Provider).order_by(Provider.created_at.desc()).limit(10),
    )
    sync_runs = await _fetch_rows(
        session,
        select(SyncRun).order_by(SyncRun.started_at.desc()).limit(15),
    )
    countries = await _fetch_rows(
        session,
        select(Country).order_by(Country.name.asc()).limit(25),
    )
    competitions = await _fetch_rows(
        session,
        select(Competition).order_by(Competition.name.asc()).limit(25),
    )
    seasons = await _fetch_rows(
        session,
        select(Season).order_by(Season.label.desc()).limit(25),
    )
    competition_seasons = await _fetch_rows(
        session,
        select(CompetitionSeason)
        .order_by(CompetitionSeason.created_at.desc())
        .limit(25),
    )
    matches = await _fetch_matches(
        session,
        _match_select().order_by(Match.kickoff_at.desc()).limit(25),
    )

    return CatalogDashboardSnapshot(
        counts=counts,
        providers=providers,
        sync_runs=sync_runs,
        countries=countries,
        competitions=competitions,
        seasons=seasons,
        competition_seasons=competition_seasons,
        matches=matches,
    )


async def build_catalog_overview(session: AsyncSession) -> CatalogOverview:
    snapshot = await build_catalog_dashboard_snapshot(session)
    return CatalogOverview(counts=snapshot.counts)


async def list_countries(
    *,
    session: AsyncSession,
    q: str | None,
    limit: int,
    offset: int = 0,
) -> list[CountrySummary]:
    stmt: Select[tuple[Country]] = (
        select(Country).order_by(Country.name.asc()).offset(offset).limit(limit)
    )

    if q:
        pattern = f"%{q.strip()}%"
        stmt = stmt.where(or_(Country.name.ilike(pattern), Country.slug.ilike(pattern)))

    result = await session.execute(stmt)
    return [
        CountrySummary.model_validate(country) for country in result.scalars().all()
    ]


async def list_competitions(
    *,
    session: AsyncSession,
    q: str | None,
    country_slug: str | None,
    limit: int,
    offset: int = 0,
) -> list[CompetitionSummary]:
    stmt: Select[tuple[Competition]] = (
        select(Competition)
        .options(selectinload(Competition.country))
        .order_by(Competition.name.asc())
        .offset(offset)
        .limit(limit)
    )

    if q:
        pattern = f"%{q.strip()}%"
        stmt = stmt.where(
            or_(Competition.name.ilike(pattern), Competition.slug.ilike(pattern))
        )

    if country_slug:
        stmt = stmt.join(Competition.country).where(Country.slug == country_slug)

    result = await session.execute(stmt)
    return [
        CompetitionSummary.model_validate(competition)
        for competition in result.scalars().all()
    ]


async def list_seasons(
    *,
    session: AsyncSession,
    competition_slug: str | None,
    current_only: bool,
    limit: int,
    offset: int = 0,
) -> list[SeasonSummary]:
    stmt = _build_seasons_stmt(
        competition_slug=competition_slug,
        current_only=current_only,
        limit=limit,
        offset=offset,
    )

    result = await session.execute(stmt)
    return [SeasonSummary.model_validate(season) for season in result.scalars().all()]


async def list_sync_runs(
    *,
    session: AsyncSession,
    scope: str | None,
    provider_slug: str | None,
    limit: int,
    offset: int = 0,
) -> list[SyncRunSummary]:
    stmt: Select[tuple[SyncRun]] = (
        select(SyncRun)
        .options(selectinload(SyncRun.provider))
        .order_by(SyncRun.started_at.desc())
        .offset(offset)
        .limit(limit)
    )

    if scope:
        stmt = stmt.where(SyncRun.scope == scope)

    if provider_slug:
        stmt = stmt.join(SyncRun.provider).where(Provider.slug == provider_slug)

    result = await session.execute(stmt)
    return [SyncRunSummary.model_validate(sync_run) for sync_run in result.scalars().all()]


async def list_teams(
    *,
    session: AsyncSession,
    q: str | None,
    country_slug: str | None,
    limit: int,
    offset: int = 0,
) -> list[Team]:
    stmt: Select[tuple[Team]] = (
        select(Team)
        .options(selectinload(Team.country))
        .order_by(Team.name.asc())
        .offset(offset)
        .limit(limit)
    )

    if q:
        pattern = f"%{q.strip()}%"
        stmt = stmt.where(or_(Team.name.ilike(pattern), Team.slug.ilike(pattern)))

    if country_slug:
        stmt = stmt.join(Team.country).where(Country.slug == country_slug)

    return await _fetch_rows(session, stmt)


async def list_players(
    *,
    session: AsyncSession,
    q: str | None,
    country_slug: str | None,
    limit: int,
    offset: int = 0,
) -> list[Player]:
    stmt: Select[tuple[Player]] = (
        select(Player)
        .options(selectinload(Player.country))
        .order_by(Player.full_name.asc())
        .offset(offset)
        .limit(limit)
    )

    if q:
        pattern = f"%{q.strip()}%"
        stmt = stmt.where(
            or_(
                Player.full_name.ilike(pattern),
                Player.short_name.ilike(pattern),
                Player.slug.ilike(pattern),
            )
        )

    if country_slug:
        stmt = stmt.join(Player.country).where(Country.slug == country_slug)

    return await _fetch_rows(session, stmt)


async def count_provider_team_mappings(
    *,
    session: AsyncSession,
    provider_slug: str,
) -> int:
    stmt = (
        select(func.count())
        .select_from(ProviderEntityMapping)
        .join(Provider, Provider.id == ProviderEntityMapping.provider_id)
        .where(
            Provider.slug == provider_slug,
            ProviderEntityMapping.entity_type == EntityType.team,
        )
    )
    result = await session.execute(stmt)
    return int(result.scalar_one() or 0)


async def count_provider_team_player_sync(
    *,
    session: AsyncSession,
    provider_slug: str,
    team_ids: list[UUID],
) -> dict[UUID, int]:
    if not team_ids:
        return {}

    stmt = (
        select(TeamMembership.team_id, func.count(func.distinct(TeamMembership.player_id)))
        .select_from(TeamMembership)
        .join(Player, Player.id == TeamMembership.player_id)
        .join(
            ProviderEntityMapping,
            ProviderEntityMapping.canonical_entity_uid == Player.entity_uid,
        )
        .join(Provider, Provider.id == ProviderEntityMapping.provider_id)
        .where(
            Provider.slug == provider_slug,
            ProviderEntityMapping.entity_type == EntityType.player,
            TeamMembership.team_id.in_(team_ids),
            TeamMembership.is_current.is_(True),
        )
        .group_by(TeamMembership.team_id)
    )
    result = await session.execute(stmt)
    return {team_id: int(count) for team_id, count in result.all()}


async def count_provider_match_player_sync(
    *,
    session: AsyncSession,
    provider_slug: str,
    match_ids: list[UUID],
) -> dict[UUID, dict[str, dict[str, int]]]:
    if not match_ids:
        return {}

    provider_slugs = expand_lineup_provider_slugs(provider_slug)
    played_player_id = case(
        (MatchPlayerAppearance.played.is_(True), MatchPlayerAppearance.player_id),
        else_=None,
    )
    stmt = (
        select(
            MatchPlayerAppearance.match_id,
            MatchPlayerAppearance.side,
            func.count(func.distinct(MatchPlayerAppearance.player_id)).label("listed_count"),
            func.count(func.distinct(played_player_id)).label("played_count"),
        )
        .select_from(MatchPlayerAppearance)
        .join(Provider, Provider.id == MatchPlayerAppearance.provider_id)
        .where(
            Provider.slug.in_(provider_slugs),
            MatchPlayerAppearance.match_id.in_(match_ids),
        )
        .group_by(MatchPlayerAppearance.match_id, MatchPlayerAppearance.side)
    )
    result = await session.execute(stmt)

    counts: dict[UUID, dict[str, dict[str, int]]] = {}
    for match_id, side, listed_count, played_count in result.all():
        side_counts = counts.setdefault(match_id, {})
        side_counts[str(side)] = {
            "listed": int(listed_count or 0),
            "played": int(played_count or 0),
        }
    return counts


async def browse_matches(
    *,
    session: AsyncSession,
    target_date: date | None,
    competition_slug: str | None,
    team_q: str | None,
    status: str | None,
    limit: int | None,
    offset: int = 0,
    timezone_name: str | None = None,
) -> list[Match]:
    stmt: Select[tuple[Match]] = _match_select().order_by(Match.kickoff_at.desc()).offset(offset)
    if limit is not None:
        stmt = stmt.limit(limit)

    if competition_slug:
        stmt = stmt.join(Match.competition).where(Competition.slug == competition_slug)

    if team_q:
        pattern = f"%{team_q.strip()}%"
        home_team = Team.__table__.alias("home_team")
        away_team = Team.__table__.alias("away_team")
        stmt = (
            stmt.join(home_team, home_team.c.id == Match.home_team_id)
            .join(away_team, away_team.c.id == Match.away_team_id)
            .where(
                or_(
                    home_team.c.name.ilike(pattern),
                    away_team.c.name.ilike(pattern),
                    home_team.c.slug.ilike(pattern),
                    away_team.c.slug.ilike(pattern),
                )
            )
        )

    if target_date is not None:
        start_of_day_local, end_of_day_local = utc_day_bounds(target_date, timezone_name)
        stmt = stmt.where(
            Match.kickoff_at >= start_of_day_local,
            Match.kickoff_at < end_of_day_local,
        )

    if status:
        normalized_status = status.strip().lower()
        if normalized_status in MatchStatus._value2member_map_:
            stmt = stmt.where(Match.status == MatchStatus(normalized_status))

    return await _fetch_matches(session, stmt)


async def get_country_by_slug(
    session: AsyncSession,
    country_slug: str,
) -> Country | None:
    result = await session.execute(select(Country).where(Country.slug == country_slug))
    return result.scalar_one_or_none()


async def get_competition_by_slug(
    session: AsyncSession,
    competition_slug: str,
) -> Competition | None:
    stmt = (
        select(Competition)
        .options(selectinload(Competition.country))
        .where(Competition.slug == competition_slug)
    )
    result = await session.execute(stmt)
    return result.scalar_one_or_none()


async def get_season_by_entity_uid(
    session: AsyncSession,
    entity_uid: str,
) -> Season | None:
    result = await session.execute(select(Season).where(Season.entity_uid == entity_uid))
    return result.scalar_one_or_none()


async def get_team_by_slug(
    session: AsyncSession,
    team_slug: str,
) -> Team | None:
    stmt = select(Team).options(selectinload(Team.country)).where(Team.slug == team_slug)
    result = await session.execute(stmt)
    return result.scalar_one_or_none()


async def get_match_by_id(
    session: AsyncSession,
    match_id: UUID,
) -> Match | None:
    stmt = _match_select().where(Match.id == match_id)
    result = await session.execute(stmt)
    return result.scalars().unique().one_or_none()


async def list_competitions_for_country(
    session: AsyncSession,
    country_slug: str,
    *,
    limit: int = 100,
) -> list[Competition]:
    stmt = (
        select(Competition)
        .options(selectinload(Competition.country))
        .join(Competition.country)
        .where(Country.slug == country_slug)
        .order_by(Competition.name.asc())
        .limit(limit)
    )
    return await _fetch_rows(session, stmt)


async def list_competitions_for_season(
    session: AsyncSession,
    season_entity_uid: str,
    *,
    limit: int = 100,
) -> list[Competition]:
    stmt = (
        select(Competition)
        .options(selectinload(Competition.country))
        .join(Competition.competition_seasons)
        .join(CompetitionSeason.season)
        .where(Season.entity_uid == season_entity_uid)
        .order_by(Competition.name.asc())
        .limit(limit)
    )
    return await _fetch_rows(session, stmt)


async def list_matches_for_country(
    session: AsyncSession,
    country_slug: str,
    *,
    limit: int = 20,
) -> list[Match]:
    stmt = (
        _match_select()
        .join(Match.competition)
        .join(Competition.country)
        .where(Country.slug == country_slug)
        .order_by(Match.kickoff_at.desc())
        .limit(limit)
    )
    return await _fetch_matches(session, stmt)


async def list_matches_for_competition(
    session: AsyncSession,
    competition_slug: str,
    *,
    limit: int = 20,
) -> list[Match]:
    stmt = (
        _match_select()
        .join(Match.competition)
        .where(Competition.slug == competition_slug)
        .order_by(Match.kickoff_at.desc())
        .limit(limit)
    )
    return await _fetch_matches(session, stmt)


async def list_matches_for_season(
    session: AsyncSession,
    season_entity_uid: str,
    *,
    limit: int = 20,
) -> list[Match]:
    stmt = (
        _match_select()
        .join(Match.season)
        .where(Season.entity_uid == season_entity_uid)
        .order_by(Match.kickoff_at.desc())
        .limit(limit)
    )
    return await _fetch_matches(session, stmt)


async def list_matches_for_team(
    session: AsyncSession,
    team_id: UUID,
    *,
    limit: int = 20,
) -> list[Match]:
    stmt = (
        _match_select()
        .where(or_(Match.home_team_id == team_id, Match.away_team_id == team_id))
        .order_by(Match.kickoff_at.desc())
        .limit(limit)
    )
    return await _fetch_matches(session, stmt)


async def _count_rows(session: AsyncSession, model) -> int:
    result = await session.execute(select(func.count()).select_from(model))
    return int(result.scalar_one())


async def _fetch_rows(session: AsyncSession, stmt):
    result = await session.execute(stmt)
    return list(result.scalars().all())


async def _fetch_matches(session: AsyncSession, stmt: Select[tuple[Match]]) -> list[Match]:
    result = await session.execute(stmt)
    return list(result.scalars().unique().all())


def _match_select() -> Select[tuple[Match]]:
    return select(Match).options(
        selectinload(Match.home_team).selectinload(Team.country),
        selectinload(Match.away_team).selectinload(Team.country),
        selectinload(Match.competition).selectinload(Competition.country),
        selectinload(Match.season),
        selectinload(Match.competition_season),
    )


def _build_seasons_stmt(
    *,
    competition_slug: str | None,
    current_only: bool,
    limit: int,
    offset: int = 0,
) -> Select[tuple[Season]]:
    if competition_slug:
        matching_season_ids = (
            select(CompetitionSeason.season_id)
            .join(Competition, Competition.id == CompetitionSeason.competition_id)
            .where(Competition.slug == competition_slug)
            .distinct()
            .subquery()
        )
        stmt: Select[tuple[Season]] = (
            select(Season)
            .join(matching_season_ids, matching_season_ids.c.season_id == Season.id)
            .order_by(Season.label.desc(), Season.id.desc())
        )
    else:
        stmt = select(Season).order_by(Season.label.desc(), Season.id.desc())

    if current_only:
        stmt = stmt.where(Season.is_current.is_(True))

    return stmt.offset(offset).limit(limit)
