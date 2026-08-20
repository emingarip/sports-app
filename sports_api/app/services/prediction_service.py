"""Prediction generation and serving.

Fits the Dixon-Coles model per competition on canonical match history, derives
all iddaa market probabilities, crosses them with the latest bulletin odds to
flag value picks, and persists everything as ``MatchPrediction`` rows. Also
produces the calibration report that backs the public transparency endpoint.
"""

from __future__ import annotations

import logging
import uuid
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.timezones import utc_day_bounds
from app.db.models.domain import (
    Match,
    MatchPrediction,
    MatchStatus,
    SnapshotPhase,
)
from app.ml.calibration import (
    expected_calibration_error,
    log_loss,
    multiclass_brier,
    reliability_bins,
)
from app.ml.dixon_coles import DixonColesParams, MatchResult, fit_dixon_coles
from app.ml.market_blend import DEFAULT_MODEL_WEIGHT, blend_markets
from app.ml.market_derivations import derive_iddaa_markets
from app.ml.value_detection import find_value_picks
from app.services.bulletin_service import BulletinService, build_market_views

logger = logging.getLogger(__name__)

MODEL_VERSION = "dc-v1"
DEFAULT_HISTORY_DAYS = 1095
DEFAULT_HALFLIFE_DAYS = 240.0


class PredictionService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    # ------------------------------------------------------------------
    # Generation
    # ------------------------------------------------------------------

    async def generate_for_date(
        self,
        *,
        target_date: date,
        timezone_name: str = "Europe/Istanbul",
        history_days: int = DEFAULT_HISTORY_DAYS,
        halflife_days: float = DEFAULT_HALFLIFE_DAYS,
        blend_model_weight: float = DEFAULT_MODEL_WEIGHT,
    ) -> dict:
        start_at, end_at = utc_day_bounds(target_date, timezone_name)
        result = await self.session.execute(
            select(Match)
            .options(selectinload(Match.home_team), selectinload(Match.away_team))
            .where(Match.kickoff_at >= start_at, Match.kickoff_at < end_at)
            .order_by(Match.kickoff_at.asc())
        )
        matches = list(result.scalars().unique().all())

        bulletin_service = BulletinService(self.session)
        ticks_by_match = await bulletin_service._load_ticks(
            [match.id for match in matches], phase=SnapshotPhase.pre
        )

        params_by_competition: dict[uuid.UUID | None, DixonColesParams | None] = {}
        stats = {
            "matches_total": len(matches),
            "predicted": 0,
            "skipped_no_model": 0,
            "value_picks": 0,
        }

        for match in matches:
            competition_id = match.competition_id
            if competition_id not in params_by_competition:
                params_by_competition[competition_id] = await self._fit_competition_model(
                    competition_id=competition_id,
                    before=start_at,
                    history_days=history_days,
                    halflife_days=halflife_days,
                )
            params = params_by_competition[competition_id]
            if params is None:
                stats["skipped_no_model"] += 1
                continue

            lambda_home, lambda_away = params.rates(
                str(match.home_team_id), str(match.away_team_id)
            )
            market_probs = derive_iddaa_markets(lambda_home, lambda_away, params.rho)

            offered = _offered_odds_from_ticks(ticks_by_match.get(match.id, []))
            # Value detection runs on the market-blended probabilities (ADR 10):
            # Shin-devigged market prob + DC prob, blended in logit space. Stored
            # market_probs stay pure DC so calibration history remains comparable;
            # each pick records both inputs for transparency.
            blend = blend_markets(market_probs, offered, model_weight=blend_model_weight)
            picks = find_value_picks(blend.probs, offered)
            stats["value_picks"] += len(picks)

            await self._upsert_prediction(
                match_id=match.id,
                lambda_home=lambda_home,
                lambda_away=lambda_away,
                rho=params.rho,
                market_probs=market_probs,
                value_picks=[
                    {
                        "market_code": pick.market_code,
                        "selection_key": pick.selection_key,
                        "model_probability": round(pick.model_probability, 6),
                        "dc_probability": round(
                            market_probs[pick.market_code][pick.selection_key], 6
                        ),
                        "market_probability": (
                            round(
                                blend.market_probs[pick.market_code][pick.selection_key], 6
                            )
                            if pick.market_code in blend.market_probs
                            else None
                        ),
                        "odds_decimal": pick.odds_decimal,
                        "implied_probability": round(pick.implied_probability, 6),
                        "expected_value": round(pick.expected_value, 6),
                        "kelly_stake": round(pick.kelly_stake, 6),
                    }
                    for pick in picks
                ],
                trained_matches=params.trained_matches,
                blend_model_weight=blend_model_weight,
                blended_markets=len(blend.blended_markets),
            )
            stats["predicted"] += 1

        await self.session.commit()
        logger.info("prediction generation finished date=%s stats=%s", target_date, stats)
        return stats

    async def _fit_competition_model(
        self,
        *,
        competition_id: uuid.UUID | None,
        before: datetime,
        history_days: int,
        halflife_days: float,
    ) -> DixonColesParams | None:
        if competition_id is None:
            return None
        cutoff = before - timedelta(days=history_days)
        result = await self.session.execute(
            select(Match)
            .where(
                Match.competition_id == competition_id,
                Match.status == MatchStatus.finished,
                Match.score_home.is_not(None),
                Match.score_away.is_not(None),
                Match.kickoff_at >= cutoff,
                Match.kickoff_at < before,
            )
            .order_by(Match.kickoff_at.asc())
        )
        history = [
            MatchResult(
                home_team=str(match.home_team_id),
                away_team=str(match.away_team_id),
                home_goals=match.score_home,
                away_goals=match.score_away,
                played_at=match.kickoff_at.date(),
            )
            for match in result.scalars().all()
        ]
        try:
            return fit_dixon_coles(history, halflife_days=halflife_days)
        except ValueError:
            logger.info(
                "competition %s skipped: insufficient history (%s matches)",
                competition_id,
                len(history),
            )
            return None

    async def _upsert_prediction(
        self,
        *,
        match_id: uuid.UUID,
        lambda_home: float,
        lambda_away: float,
        rho: float,
        market_probs: dict,
        value_picks: list,
        trained_matches: int,
        blend_model_weight: float,
        blended_markets: int,
    ) -> None:
        rounded_probs = {
            market: {selection: round(prob, 6) for selection, prob in selections.items()}
            for market, selections in market_probs.items()
        }
        result = await self.session.execute(
            select(MatchPrediction).where(
                MatchPrediction.match_id == match_id,
                MatchPrediction.model_version == MODEL_VERSION,
                MatchPrediction.phase == SnapshotPhase.pre,
            )
        )
        prediction = result.scalar_one_or_none()
        if prediction is None:
            prediction = MatchPrediction(
                match_id=match_id,
                model_version=MODEL_VERSION,
                phase=SnapshotPhase.pre,
                generated_at=datetime.now(UTC),
            )
            self.session.add(prediction)
        prediction.generated_at = datetime.now(UTC)
        prediction.lambda_home = lambda_home
        prediction.lambda_away = lambda_away
        prediction.rho = rho
        prediction.market_probs = rounded_probs
        prediction.value_picks = value_picks
        prediction.metadata_json = {
            "trained_matches": trained_matches,
            "blend_model_weight": blend_model_weight,
            "blended_markets": blended_markets,
        }

    # ------------------------------------------------------------------
    # Serving
    # ------------------------------------------------------------------

    async def get_prediction(self, *, match_id: uuid.UUID) -> MatchPrediction | None:
        result = await self.session.execute(
            select(MatchPrediction)
            .where(MatchPrediction.match_id == match_id)
            .order_by(MatchPrediction.generated_at.desc())
            .limit(1)
        )
        return result.scalar_one_or_none()

    async def value_picks_for_date(
        self,
        *,
        target_date: date,
        timezone_name: str = "Europe/Istanbul",
        min_expected_value: float = 0.0,
    ) -> list[dict]:
        start_at, end_at = utc_day_bounds(target_date, timezone_name)
        result = await self.session.execute(
            select(MatchPrediction, Match)
            .join(Match, Match.id == MatchPrediction.match_id)
            .options(selectinload(Match.home_team), selectinload(Match.away_team))
            .where(Match.kickoff_at >= start_at, Match.kickoff_at < end_at)
            .order_by(Match.kickoff_at.asc())
        )
        items: list[dict] = []
        for prediction, match in result.unique().all():
            for pick in prediction.value_picks or []:
                if pick.get("expected_value", 0.0) < min_expected_value:
                    continue
                items.append(
                    {
                        "match_id": str(match.id),
                        "home_team": match.home_team.name,
                        "away_team": match.away_team.name,
                        "kickoff_at": match.kickoff_at.isoformat(),
                        **pick,
                    }
                )
        items.sort(key=lambda item: item.get("expected_value", 0.0), reverse=True)
        return items

    async def predictions_for_date(
        self,
        *,
        target_date: date,
        timezone_name: str = "Europe/Istanbul",
    ) -> list[dict]:
        """All predictions for a bulletin day in one payload (bridge sync)."""
        start_at, end_at = utc_day_bounds(target_date, timezone_name)
        result = await self.session.execute(
            select(MatchPrediction, Match)
            .join(Match, Match.id == MatchPrediction.match_id)
            .where(Match.kickoff_at >= start_at, Match.kickoff_at < end_at)
            .order_by(Match.kickoff_at.asc())
        )
        return [
            {
                "match_id": str(match.id),
                "model_version": prediction.model_version,
                "generated_at": prediction.generated_at.isoformat(),
                "lambda_home": prediction.lambda_home,
                "lambda_away": prediction.lambda_away,
                "rho": prediction.rho,
                "market_probs": prediction.market_probs or {},
                "value_picks": prediction.value_picks or [],
            }
            for prediction, match in result.unique().all()
        ]

    async def calibration_report(self, *, days: int = 120) -> dict:
        cutoff = datetime.now(UTC) - timedelta(days=days)
        result = await self.session.execute(
            select(MatchPrediction, Match)
            .join(Match, Match.id == MatchPrediction.match_id)
            .where(
                Match.status == MatchStatus.finished,
                Match.score_home.is_not(None),
                Match.score_away.is_not(None),
                MatchPrediction.generated_at >= cutoff,
            )
        )
        ms_rows: list[dict[str, float]] = []
        ms_outcomes: list[str] = []
        home_probs: list[float] = []
        home_outcomes: list[int] = []
        over25_probs: list[float] = []
        over25_outcomes: list[int] = []

        for prediction, match in result.unique().all():
            probs = prediction.market_probs or {}
            ms = probs.get("MS")
            if ms and all(key in ms for key in ("home", "draw", "away")):
                if match.score_home > match.score_away:
                    outcome = "home"
                elif match.score_home < match.score_away:
                    outcome = "away"
                else:
                    outcome = "draw"
                ms_rows.append({key: float(ms[key]) for key in ("home", "draw", "away")})
                ms_outcomes.append(outcome)
                home_probs.append(float(ms["home"]))
                home_outcomes.append(1 if outcome == "home" else 0)
            au = probs.get("AU_2_5")
            if au and "over" in au:
                over25_probs.append(float(au["over"]))
                over25_outcomes.append(
                    1 if (match.score_home + match.score_away) > 2.5 else 0
                )

        report: dict = {
            "model_version": MODEL_VERSION,
            "window_days": days,
            "sample_size_1x2": len(ms_rows),
            "sample_size_over25": len(over25_probs),
        }
        if ms_rows:
            report["brier_1x2"] = round(multiclass_brier(ms_rows, ms_outcomes), 6)
            report["log_loss_home"] = round(log_loss(home_probs, home_outcomes), 6)
            report["ece_home"] = round(
                expected_calibration_error(home_probs, home_outcomes), 6
            )
            report["reliability_home"] = [
                {
                    "lower": bin_.lower,
                    "upper": bin_.upper,
                    "count": bin_.count,
                    "mean_predicted": round(bin_.mean_predicted, 4),
                    "observed_rate": round(bin_.observed_rate, 4),
                }
                for bin_ in reliability_bins(home_probs, home_outcomes)
                if bin_.count > 0
            ]
        if over25_probs:
            report["log_loss_over25"] = round(log_loss(over25_probs, over25_outcomes), 6)
            report["ece_over25"] = round(
                expected_calibration_error(over25_probs, over25_outcomes), 6
            )
        return report


def _offered_odds_from_ticks(ticks: list) -> dict[str, dict[str, float]]:
    """Latest bulletin odds keyed by market code then selection key."""
    from app.services.bulletin_service import TickRow  # local import to avoid cycle confusion

    rows = [tick if isinstance(tick, TickRow) else TickRow.from_model(tick) for tick in ticks]
    offered: dict[str, dict[str, float]] = {}
    for view in build_market_views(rows):
        offered[view.market_code] = {
            selection.selection_key: selection.odds
            for selection in view.selections
            if not selection.suspended
        }
    return offered
