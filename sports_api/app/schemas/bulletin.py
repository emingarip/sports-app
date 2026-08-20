from datetime import date, datetime

from pydantic import BaseModel


class BulletinSelectionOdds(BaseModel):
    selection_key: str
    label_tr: str | None = None
    odds: float
    opening_odds: float | None = None
    implied_prob: float | None = None
    normalized_prob: float | None = None
    movement_pct: float | None = None
    is_dropping: bool = False
    suspended: bool = False


class BulletinMarketOdds(BaseModel):
    market_code: str
    market_type: str
    name_tr: str
    line_value: float | None = None
    last_tick_at: datetime | None = None
    selections: list[BulletinSelectionOdds] = []


class BulletinMatch(BaseModel):
    match_id: str
    kickoff_at: datetime
    status: str
    competition_name: str | None = None
    home_team: str
    away_team: str
    mbs: int | None = None
    markets: list[BulletinMarketOdds] = []


class BulletinResponse(BaseModel):
    target_date: date
    timezone: str
    match_count: int
    matches: list[BulletinMatch] = []


class OddsHistoryPoint(BaseModel):
    tick_time: datetime
    odds: float
    implied_prob: float | None = None


class SelectionOddsHistory(BaseModel):
    market_code: str
    market_type: str
    name_tr: str
    line_value: float | None = None
    selection_key: str
    label_tr: str | None = None
    points: list[OddsHistoryPoint] = []


class MatchOddsResponse(BaseModel):
    match_id: str
    home_team: str
    away_team: str
    kickoff_at: datetime
    markets: list[BulletinMarketOdds] = []
    history: list[SelectionOddsHistory] = []
