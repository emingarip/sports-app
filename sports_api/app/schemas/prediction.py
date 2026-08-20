from datetime import datetime

from pydantic import BaseModel


class ValuePickItem(BaseModel):
    market_code: str
    selection_key: str
    model_probability: float
    # Blend inputs (ADR 10): raw Dixon-Coles probability and the Shin
    # de-vigged market probability behind ``model_probability``. Optional so
    # predictions stored before the blend keep deserialising.
    dc_probability: float | None = None
    market_probability: float | None = None
    odds_decimal: float
    implied_probability: float
    expected_value: float
    kelly_stake: float


class SelectionComparison(BaseModel):
    selection_key: str
    label_tr: str | None = None
    model_probability: float
    odds: float | None = None
    implied_probability: float | None = None
    expected_value: float | None = None
    is_value: bool = False


class MarketComparison(BaseModel):
    market_code: str
    name_tr: str
    line_value: float | None = None
    selections: list[SelectionComparison] = []


class MatchPredictionResponse(BaseModel):
    match_id: str
    model_version: str
    phase: str
    generated_at: datetime
    lambda_home: float | None = None
    lambda_away: float | None = None
    rho: float | None = None
    trained_matches: int | None = None
    market_probs: dict[str, dict[str, float]] = {}
    value_picks: list[ValuePickItem] = []
    comparisons: list[MarketComparison] = []


class BulletinValuePick(ValuePickItem):
    match_id: str
    home_team: str
    away_team: str
    kickoff_at: datetime


class PredictionRunResponse(BaseModel):
    target_date: str
    matches_total: int
    predicted: int
    skipped_no_model: int
    value_picks: int
    # Predictions where the model had never seen one of the teams and
    # fell back to league-average ratings.
    low_confidence: int = 0
