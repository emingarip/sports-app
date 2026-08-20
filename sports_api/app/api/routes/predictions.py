from datetime import date, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db_session, verify_internal_token
from app.core.timezones import DEFAULT_TIMEZONE, canonical_timezone_name
from app.domain.iddaa_markets import get_market_by_code
from app.ml.value_detection import DEFAULT_EV_THRESHOLD, expected_value
from app.schemas.prediction import (
    BulletinValuePick,
    MarketComparison,
    MatchPredictionResponse,
    PredictionRunResponse,
    SelectionComparison,
    ValuePickItem,
)
from app.services.bulletin_service import BulletinService
from app.services.prediction_service import PredictionService

router = APIRouter(tags=["predictions"])


@router.get("/matches/{match_id}/prediction", response_model=MatchPredictionResponse)
async def get_match_prediction(
    match_id: UUID,
    session: AsyncSession = Depends(get_db_session),
) -> MatchPredictionResponse:
    service = PredictionService(session)
    prediction = await service.get_prediction(match_id=match_id)
    if prediction is None:
        raise HTTPException(status_code=404, detail="No prediction for this match yet.")

    bulletin_service = BulletinService(session)
    odds_response = await bulletin_service.get_match_odds(match_id=match_id)

    offered: dict[str, dict[str, dict]] = {}
    if odds_response is not None:
        for market in odds_response.markets:
            offered[market.market_code] = {
                selection.selection_key: selection for selection in market.selections
            }

    comparisons: list[MarketComparison] = []
    for market_code, selections in (prediction.market_probs or {}).items():
        market_def = get_market_by_code(market_code)
        if market_def is None:
            continue
        comparison_rows: list[SelectionComparison] = []
        offered_selections = offered.get(market_code, {})
        for selection_key, model_probability in selections.items():
            offered_selection = offered_selections.get(selection_key)
            odds = offered_selection.odds if offered_selection is not None else None
            ev = expected_value(model_probability, odds) if odds else None
            comparison_rows.append(
                SelectionComparison(
                    selection_key=selection_key,
                    label_tr=market_def.selection_label(selection_key),
                    model_probability=round(model_probability, 4),
                    odds=odds,
                    implied_probability=round(1.0 / odds, 4) if odds else None,
                    expected_value=round(ev, 4) if ev is not None else None,
                    is_value=bool(ev is not None and ev >= DEFAULT_EV_THRESHOLD),
                )
            )
        comparisons.append(
            MarketComparison(
                market_code=market_code,
                name_tr=market_def.name_tr,
                line_value=market_def.line_value,
                selections=comparison_rows,
            )
        )

    metadata = prediction.metadata_json or {}
    return MatchPredictionResponse(
        match_id=str(prediction.match_id),
        model_version=prediction.model_version,
        phase=prediction.phase.value,
        generated_at=prediction.generated_at,
        lambda_home=prediction.lambda_home,
        lambda_away=prediction.lambda_away,
        rho=prediction.rho,
        trained_matches=metadata.get("trained_matches"),
        market_probs=prediction.market_probs or {},
        value_picks=[ValuePickItem(**pick) for pick in prediction.value_picks or []],
        comparisons=comparisons,
    )


@router.get("/bulletin/value-picks", response_model=list[BulletinValuePick])
async def get_bulletin_value_picks(
    target_date: date | None = Query(default=None, alias="date"),
    timezone_name: str = Query(default=DEFAULT_TIMEZONE, alias="tz"),
    min_ev: float = Query(default=0.0, ge=0.0),
    session: AsyncSession = Depends(get_db_session),
) -> list[BulletinValuePick]:
    try:
        normalized_timezone = canonical_timezone_name(timezone_name)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if target_date is None:
        target_date = datetime.now().date()

    service = PredictionService(session)
    picks = await service.value_picks_for_date(
        target_date=target_date,
        timezone_name=normalized_timezone,
        min_expected_value=min_ev,
    )
    return [BulletinValuePick(**pick) for pick in picks]


@router.get("/bulletin/predictions")
async def get_bulletin_predictions(
    target_date: date | None = Query(default=None, alias="date"),
    timezone_name: str = Query(default=DEFAULT_TIMEZONE, alias="tz"),
    session: AsyncSession = Depends(get_db_session),
) -> list[dict]:
    try:
        normalized_timezone = canonical_timezone_name(timezone_name)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if target_date is None:
        target_date = datetime.now().date()

    service = PredictionService(session)
    return await service.predictions_for_date(
        target_date=target_date,
        timezone_name=normalized_timezone,
    )


@router.get("/model/calibration")
async def get_model_calibration(
    days: int = Query(default=120, ge=7, le=730),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    service = PredictionService(session)
    return await service.calibration_report(days=days)


@router.post("/internal/predictions/run", response_model=PredictionRunResponse)
async def run_predictions(
    target_date: date | None = Query(default=None),
    timezone_name: str = Query(default=DEFAULT_TIMEZONE, alias="tz"),
    _: None = Depends(verify_internal_token),
    session: AsyncSession = Depends(get_db_session),
) -> PredictionRunResponse:
    try:
        normalized_timezone = canonical_timezone_name(timezone_name)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if target_date is None:
        target_date = datetime.now().date()

    service = PredictionService(session)
    stats = await service.generate_for_date(
        target_date=target_date,
        timezone_name=normalized_timezone,
    )
    return PredictionRunResponse(target_date=target_date.isoformat(), **stats)
