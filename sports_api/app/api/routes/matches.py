from datetime import date, datetime
from enum import Enum
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db_session
from app.core.timezones import DEFAULT_TIMEZONE, canonical_timezone_name
from app.schemas.match import MatchSummary
from app.services.match_feature_snapshot_service import MatchFeatureSnapshotService
from app.services.match_service import list_matches

router = APIRouter(prefix="/matches", tags=["matches"])


@router.get("", response_model=list[MatchSummary])
async def get_matches(
    target_date: date | None = Query(default=None, alias="date"),
    timezone_name: str = Query(default=DEFAULT_TIMEZONE, alias="tz"),
    limit: int = Query(default=100, ge=1, le=500),
    session: AsyncSession = Depends(get_db_session),
) -> list[MatchSummary]:
    try:
        normalized_timezone = canonical_timezone_name(timezone_name)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    return await list_matches(
        session=session,
        target_date=target_date,
        limit=limit,
        timezone_name=normalized_timezone,
    )


@router.get("/{match_id}/snapshots")
async def get_match_snapshots(
    match_id: UUID,
    phase: str | None = Query(default=None),
    limit: int = Query(default=500, ge=1, le=2000),
    session: AsyncSession = Depends(get_db_session),
) -> list[dict]:
    service = MatchFeatureSnapshotService(session)
    rows = await service.list_snapshots(match_id=match_id, phase=phase, limit=limit)
    return [_serialize_snapshot(item) for item in rows]


@router.get("/{match_id}/snapshots/latest")
async def get_latest_match_snapshot(
    match_id: UUID,
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    service = MatchFeatureSnapshotService(session)
    row = await service.latest_snapshot(match_id=match_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Match snapshot not found.")
    return _serialize_snapshot(row)


def _serialize_snapshot(snapshot) -> dict:
    payload: dict[str, object] = {}
    mapper = getattr(snapshot, "__mapper__", None)
    if mapper is not None:
        for attribute in mapper.column_attrs:
            value = getattr(snapshot, attribute.key)
            payload[attribute.key] = _serialize_snapshot_value(value)
        return payload

    for column in snapshot.__table__.columns:
        attribute_name = getattr(column, "key", None) or column.name
        value = getattr(snapshot, attribute_name)
        payload[attribute_name] = _serialize_snapshot_value(value)
    return payload


def _serialize_snapshot_value(value):
    if isinstance(value, Enum):
        return value.value
    if isinstance(value, (UUID, datetime, date)):
        return str(value) if isinstance(value, UUID) else value.isoformat()
    if isinstance(value, dict):
        return {str(key): _serialize_snapshot_value(item) for key, item in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [_serialize_snapshot_value(item) for item in value]
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    return str(value)
