import uuid
from datetime import date, datetime

from pydantic import BaseModel

from app.db.models.domain import SyncRunStatus


class SyncTriggerResponse(BaseModel):
    accepted: bool
    provider_slug: str
    scope: str
    target_date: date | None = None
    sync_run_id: uuid.UUID | None = None
    status: SyncRunStatus | None = None
    queued_at: datetime | None = None
    stats: dict[str, int] | None = None
    error_code: int | None = None
    message: str
