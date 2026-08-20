import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict

from app.db.models.domain import CompetitionType, SyncRunStatus


class CountrySummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    entity_uid: str
    name: str
    slug: str
    iso_code2: str | None = None
    iso_code3: str | None = None


class CountryBrief(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    entity_uid: str
    name: str
    slug: str


class CompetitionSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    entity_uid: str
    name: str
    slug: str
    competition_type: CompetitionType
    country: CountryBrief | None = None


class SeasonSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    entity_uid: str
    label: str
    start_date: date | None = None
    end_date: date | None = None
    is_current: bool


class ProviderSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    slug: str
    name: str


class SyncRunSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    scope: str
    status: SyncRunStatus
    target_date: date | None = None
    stats: dict
    error_message: str | None = None
    started_at: datetime
    completed_at: datetime | None = None
    provider: ProviderSummary


class CatalogOverview(BaseModel):
    counts: dict[str, int]
