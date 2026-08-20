from datetime import date

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db_session, verify_internal_token
from app.schemas.sync import SyncTriggerResponse
from app.services.sync_service import SyncService

router = APIRouter(prefix="/internal/sync", tags=["sync"])


@router.post("/providers/{provider_slug}", response_model=SyncTriggerResponse)
async def trigger_provider_sync(
    provider_slug: str,
    scope: str = Query(default="matches"),
    target_date: date | None = Query(default=None),
    category_id: str | None = Query(default=None),
    tournament_id: str | None = Query(default=None),
    _: None = Depends(verify_internal_token),
    session: AsyncSession = Depends(get_db_session),
) -> SyncTriggerResponse:
    service = SyncService(session)
    return await service.trigger_provider_sync(
        provider_slug=provider_slug,
        scope=scope,
        target_date=target_date,
        category_id=category_id,
        tournament_id=tournament_id,
    )
