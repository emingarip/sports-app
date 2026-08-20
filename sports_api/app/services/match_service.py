from datetime import date

from sqlalchemy import Select, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.timezones import convert_datetime, utc_day_bounds
from app.db.models.domain import Match
from app.schemas.match import CompetitionBrief, MatchSummary, SeasonBrief, TeamBrief


async def list_matches(
    *,
    session: AsyncSession,
    target_date: date | None,
    limit: int,
    timezone_name: str | None = None,
) -> list[MatchSummary]:
    stmt: Select[tuple[Match]] = (
        select(Match)
        .options(
            selectinload(Match.home_team),
            selectinload(Match.away_team),
            selectinload(Match.competition),
            selectinload(Match.season),
        )
        .order_by(Match.kickoff_at.asc())
        .limit(limit)
    )

    if target_date is not None:
        start_of_day, end_of_day = utc_day_bounds(target_date, timezone_name)
        stmt = stmt.where(Match.kickoff_at >= start_of_day, Match.kickoff_at < end_of_day)

    result = await session.execute(stmt)
    matches = result.scalars().all()

    return [serialize_match(match, timezone_name=timezone_name) for match in matches]


def serialize_match(match: Match, *, timezone_name: str | None = None) -> MatchSummary:
    return MatchSummary(
        id=match.id,
        entity_uid=match.entity_uid,
        kickoff_at=convert_datetime(match.kickoff_at, timezone_name),
        status=match.status,
        home_team=TeamBrief.model_validate(match.home_team),
        away_team=TeamBrief.model_validate(match.away_team),
        competition=(
            CompetitionBrief.model_validate(match.competition) if match.competition is not None else None
        ),
        season=SeasonBrief.model_validate(match.season) if match.season is not None else None,
        score_home=match.score_home,
        score_away=match.score_away,
        score_home_ht=match.score_home_ht,
        score_away_ht=match.score_away_ht,
    )
