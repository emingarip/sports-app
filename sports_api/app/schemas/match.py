import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict

from app.db.models.domain import CompetitionType, MatchStatus


class TeamBrief(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    entity_uid: str
    name: str
    short_name: str | None = None


class CompetitionBrief(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    entity_uid: str
    name: str
    competition_type: CompetitionType


class SeasonBrief(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    entity_uid: str
    label: str


class MatchSummary(BaseModel):
    id: uuid.UUID
    entity_uid: str
    kickoff_at: datetime
    status: MatchStatus
    home_team: TeamBrief
    away_team: TeamBrief
    competition: CompetitionBrief | None = None
    season: SeasonBrief | None = None
    score_home: int | None = None
    score_away: int | None = None
    # resolve-coupons voids every half-time market when these are absent.
    score_home_ht: int | None = None
    score_away_ht: int | None = None
