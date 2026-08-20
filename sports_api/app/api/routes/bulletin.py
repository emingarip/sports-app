from datetime import date, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db_session
from app.core.timezones import DEFAULT_TIMEZONE, canonical_timezone_name
from app.domain.iddaa_markets import IDDAA_MARKETS, get_market_by_code
from app.schemas.bulletin import BulletinResponse, MatchOddsResponse
from app.services.bulletin_service import BulletinService

router = APIRouter(tags=["bulletin"])


@router.get("/bulletin", response_model=BulletinResponse)
async def get_bulletin(
    target_date: date | None = Query(default=None, alias="date"),
    timezone_name: str = Query(default=DEFAULT_TIMEZONE, alias="tz"),
    competition: str | None = Query(default=None),
    markets: str | None = Query(
        default=None,
        description="Comma separated iddaa market codes (e.g. MS,AU_2_5,KG).",
    ),
    limit: int = Query(default=500, ge=1, le=1000),
    session: AsyncSession = Depends(get_db_session),
) -> BulletinResponse:
    try:
        normalized_timezone = canonical_timezone_name(timezone_name)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    market_codes: set[str] | None = None
    if markets:
        market_codes = set()
        for raw_code in markets.split(","):
            market = get_market_by_code(raw_code)
            if market is None:
                raise HTTPException(
                    status_code=422,
                    detail=(
                        f"Unknown market code: {raw_code.strip()}. "
                        f"Valid codes: {', '.join(m.code for m in IDDAA_MARKETS)}"
                    ),
                )
            market_codes.add(market.code)

    if target_date is None:
        target_date = datetime.now().date()

    service = BulletinService(session)
    return await service.get_bulletin(
        target_date=target_date,
        timezone_name=normalized_timezone,
        competition_query=competition,
        market_codes=market_codes,
        limit=limit,
    )


@router.get("/matches/{match_id}/odds", response_model=MatchOddsResponse)
async def get_match_odds(
    match_id: UUID,
    session: AsyncSession = Depends(get_db_session),
) -> MatchOddsResponse:
    service = BulletinService(session)
    response = await service.get_match_odds(match_id=match_id)
    if response is None:
        raise HTTPException(status_code=404, detail="Match not found.")
    return response
