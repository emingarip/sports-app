from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db_session
from app.schemas.catalog import (
    CatalogOverview,
    CompetitionSummary,
    CountrySummary,
    SeasonSummary,
    SyncRunSummary,
)
from app.services.catalog_service import (
    build_catalog_overview,
    list_competitions,
    list_countries,
    list_seasons,
    list_sync_runs,
)

router = APIRouter(tags=["catalog"])


@router.get("/catalog/overview", response_model=CatalogOverview)
async def get_catalog_overview(
    session: AsyncSession = Depends(get_db_session),
) -> CatalogOverview:
    return await build_catalog_overview(session)


@router.get("/countries", response_model=list[CountrySummary])
async def get_countries(
    q: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    session: AsyncSession = Depends(get_db_session),
) -> list[CountrySummary]:
    return await list_countries(session=session, q=q, limit=limit)


@router.get("/competitions", response_model=list[CompetitionSummary])
async def get_competitions(
    q: str | None = Query(default=None),
    country_slug: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    session: AsyncSession = Depends(get_db_session),
) -> list[CompetitionSummary]:
    return await list_competitions(
        session=session,
        q=q,
        country_slug=country_slug,
        limit=limit,
    )


@router.get("/seasons", response_model=list[SeasonSummary])
async def get_seasons(
    competition_slug: str | None = Query(default=None),
    current_only: bool = Query(default=False),
    limit: int = Query(default=100, ge=1, le=500),
    session: AsyncSession = Depends(get_db_session),
) -> list[SeasonSummary]:
    return await list_seasons(
        session=session,
        competition_slug=competition_slug,
        current_only=current_only,
        limit=limit,
    )


@router.get("/sync-runs", response_model=list[SyncRunSummary])
async def get_sync_runs(
    scope: str | None = Query(default=None),
    provider_slug: str | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=200),
    session: AsyncSession = Depends(get_db_session),
) -> list[SyncRunSummary]:
    return await list_sync_runs(
        session=session,
        scope=scope,
        provider_slug=provider_slug,
        limit=limit,
    )
