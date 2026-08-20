"""Prediction generation and serving.

Fits the Dixon-Coles model per competition on canonical match history, derives
all iddaa market probabilities, crosses them with the latest bulletin odds to
flag value picks, and persists everything as ``MatchPrediction`` rows. Also
produces the calibration report that backs the public transparency endpoint.
"""

from __future__ import annotations

import logging
import math
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
from app.ml.backtest import SettledBet, compare_stakings
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
            "low_confidence": 0,
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

            home_key = str(match.home_team_id)
            away_key = str(match.away_team_id)
            # DixonColesParams.rates() falls back to league-average ratings for
            # a team it has never seen, which silently published a prediction
            # that looked as trustworthy as any other. Promoted sides, cup
            # fixtures and lower divisions hit this constantly, so the flag is
            # recorded and surfaced instead of being swallowed.
            low_confidence = not (
                params.knows_team(home_key) and params.knows_team(away_key)
            )
            if low_confidence:
                stats["low_confidence"] += 1

            lambda_home, lambda_away = params.rates(home_key, away_key)
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
                blended_probs=blend.probs,
                low_confidence=low_confidence,
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
                        # The price the pick was flagged at. Closing line value
                        # is measured against this later
                        # (`clv_report`), so it has to be recorded now -
                        # the tick history alone cannot say which price the
                        # model actually acted on.
                        "taken_odds": pick.odds_decimal,
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
        blended_probs: dict,
        low_confidence: bool,
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
            # Stored market_probs stay pure Dixon-Coles so the calibration
            # history remains comparable, but the value picks a user sees come
            # from the blend. Keeping both lets calibration_report() measure the
            # probability that was actually shown (roadmap 2.5 / ADR 10).
            "blended_probs": {
                market: {
                    selection: round(prob, 6)
                    for selection, prob in selections.items()
                }
                for market, selections in blended_probs.items()
            },
            "low_confidence": low_confidence,
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

    async def _settled_value_picks(self, *, days: int) -> list[dict]:
        """Value picks on finished matches, paired with their closing price.

        The closing price is the latest pre-match tick for that selection: the
        bulletin sync writes one row per hour, so the last one before kickoff
        is the closing line.
        """
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
            .order_by(Match.kickoff_at.asc())
        )
        rows = list(result.unique().all())
        if not rows:
            return []

        bulletin_service = BulletinService(self.session)
        ticks_by_match = await bulletin_service._load_ticks(
            [match.id for _, match in rows], phase=SnapshotPhase.pre
        )

        settled: list[dict] = []
        for prediction, match in rows:
            closing = _closing_odds_from_ticks(ticks_by_match.get(match.id, []))
            for pick in prediction.value_picks or []:
                market_code = pick.get("market_code")
                selection_key = pick.get("selection_key")
                if not market_code or not selection_key:
                    continue
                won = _outcome_for_selection(
                    market_code, selection_key, match.score_home, match.score_away
                )
                if won is None:
                    continue
                taken = pick.get("taken_odds") or pick.get("odds_decimal")
                if not taken or taken <= 1.0:
                    continue
                settled.append(
                    {
                        "match_id": str(match.id),
                        "kickoff_at": match.kickoff_at,
                        "market_code": market_code,
                        "selection_key": selection_key,
                        "probability": float(pick.get("model_probability", 0.0)),
                        "taken_odds": float(taken),
                        "closing_odds": closing.get(market_code, {}).get(selection_key),
                        "won": won,
                    }
                )
        return settled

    async def backtest_report(
        self,
        *,
        days: int = 120,
        starting_bankroll: float = 100.0,
        flat_stake: float = 1.0,
    ) -> dict:
        """Replay settled value picks as a bankroll simulation.

        Answers the second question of roadmap 2.5 - "does the model make
        money" - which calibration metrics cannot. Until this reports a
        meaningful sample the client keeps its beta label on every verdict.
        """
        settled = await self._settled_value_picks(days=days)
        report: dict = {
            "model_version": MODEL_VERSION,
            "window_days": days,
            "sample_size": len(settled),
        }
        if not settled:
            report["note"] = (
                "No settled value picks in the window yet; the model has not "
                "produced a measurable track record."
            )
            return report

        bets = [
            SettledBet(
                probability=item["probability"],
                odds_decimal=item["taken_odds"],
                won=item["won"],
            )
            for item in settled
        ]
        staking = compare_stakings(
            bets, starting_bankroll=starting_bankroll, flat_stake=flat_stake
        )
        report["staking"] = {
            name: {
                "n_bets": result.n_bets,
                "n_skipped": result.n_skipped,
                "total_staked": result.total_staked,
                "profit": result.profit,
                "roi": result.roi,
                "hit_rate": result.hit_rate,
                "max_drawdown": result.max_drawdown,
                "final_bankroll": result.final_bankroll,
            }
            for name, result in staking.items()
        }
        report["clv"] = _clv_summary(settled)
        return report

    async def clv_report(self, *, days: int = 120) -> dict:
        """Closing line value only, without the bankroll simulation."""
        settled = await self._settled_value_picks(days=days)
        return {
            "model_version": MODEL_VERSION,
            "window_days": days,
            "sample_size": len(settled),
            **_clv_summary(settled),
        }

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
        # Two variants on purpose. ``market_probs`` holds the pure Dixon-Coles
        # output, which keeps the calibration history comparable across model
        # versions - but the value picks a user actually sees come from the
        # market blend. Measuring only the former means the number shown to
        # users is never checked (roadmap 2.5 / ADR 10).
        variants: dict[str, _CalibrationAccumulator] = {
            "dc": _CalibrationAccumulator(),
            "blended": _CalibrationAccumulator(),
        }

        for prediction, match in result.unique().all():
            outcome = (
                "home"
                if match.score_home > match.score_away
                else "away"
                if match.score_home < match.score_away
                else "draw"
            )
            over25 = 1 if (match.score_home + match.score_away) > 2.5 else 0
            metadata = prediction.metadata_json or {}
            sources = {
                "dc": prediction.market_probs or {},
                # Older rows predate blended_probs; they simply do not
                # contribute to the blended variant rather than silently
                # falling back to the DC numbers and inflating the sample.
                "blended": metadata.get("blended_probs") or {},
            }
            for name, probs in sources.items():
                variants[name].add(probs, outcome=outcome, over25=over25)

        report: dict = {
            "model_version": MODEL_VERSION,
            "window_days": days,
            "sample_size_1x2": variants["dc"].sample_1x2,
            "sample_size_over25": variants["dc"].sample_over25,
        }
        report.update(variants["dc"].summarize())
        report["variants"] = {
            name: {
                "sample_size_1x2": accumulator.sample_1x2,
                "sample_size_over25": accumulator.sample_over25,
                **accumulator.summarize(),
            }
            for name, accumulator in variants.items()
        }
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


# ----------------------------------------------------------------------
# Closing line value and bankroll backtest
# ----------------------------------------------------------------------
#
# Roadmap principle 0.1.4 makes CLV the platform's measure of skill and 2.5
# says "calibrated" and "profitable" are separate claims. Both were unmet:
# CLV existed only on the tipster side and `app/ml/backtest.py` was imported
# by nothing but its own tests. These helpers close that loop by replaying
# settled value picks against the closing price.


def _outcome_for_selection(
    market_code: str,
    selection_key: str,
    score_home: int,
    score_away: int,
) -> bool | None:
    """Did this selection win? ``None`` when the market cannot be settled.

    Deliberately covers only the full-time markets that a final score can
    settle. Half-time markets need a half-time score the canonical schema does
    not carry yet, and guessing would poison the very numbers this module
    exists to measure.
    """
    total = score_home + score_away

    if market_code == "MS":
        if score_home > score_away:
            return selection_key == "home"
        if score_home < score_away:
            return selection_key == "away"
        return selection_key == "draw"

    if market_code == "CS":
        return {
            "home_draw": score_home >= score_away,
            "home_away": score_home != score_away,
            "draw_away": score_home <= score_away,
        }.get(selection_key)

    if market_code in {"AU_1_5", "AU_2_5", "AU_3_5"}:
        line = {"AU_1_5": 1.5, "AU_2_5": 2.5, "AU_3_5": 3.5}[market_code]
        over = total > line
        return over if selection_key == "over" else (not over if selection_key == "under" else None)

    if market_code == "KG":
        both = score_home >= 1 and score_away >= 1
        return both if selection_key == "yes" else (not both if selection_key == "no" else None)

    if market_code == "TG":
        bucket = (
            "0_1" if total <= 1 else "2_3" if total <= 3 else "4_5" if total <= 5 else "6_plus"
        )
        return selection_key == bucket

    if market_code in {"H_MS_1", "H_MS_MINUS_1"}:
        line = 1.0 if market_code == "H_MS_1" else -1.0
        adjusted = score_home + line - score_away
        if adjusted > 1e-9:
            return selection_key == "home"
        if adjusted < -1e-9:
            return selection_key == "away"
        return selection_key == "draw"

    return None


def _closing_odds_from_ticks(ticks: list) -> dict[str, dict[str, float]]:
    """Latest pre-match odds per market/selection, i.e. the closing line."""
    from app.services.bulletin_service import TickRow

    rows = [tick if isinstance(tick, TickRow) else TickRow.from_model(tick) for tick in ticks]
    closing: dict[str, dict[str, float]] = {}
    for view in build_market_views(rows):
        closing[view.market_code] = {
            selection.selection_key: selection.odds for selection in view.selections
        }
    return closing


def _clv_summary(settled: list[dict]) -> dict:
    """Closing line value across settled picks.

    CLV is expressed as the log ratio of the taken price to the closing price:
    positive means the model bet before the market moved its way. Averaging log
    ratios rather than percentages keeps a 2.00 -> 1.80 move symmetric with
    1.80 -> 2.00, which a plain percentage does not.
    """
    ratios = [
        math.log(item["taken_odds"] / item["closing_odds"])
        for item in settled
        if item.get("closing_odds") and item["closing_odds"] > 1.0
    ]
    if not ratios:
        return {"clv_sample": 0, "mean_clv": None, "clv_positive_rate": None}
    return {
        "clv_sample": len(ratios),
        "mean_clv": round(sum(ratios) / len(ratios), 6),
        "clv_positive_rate": round(
            sum(1 for value in ratios if value > 0) / len(ratios), 6
        ),
    }


class _CalibrationAccumulator:
    """Collects the rows one calibration variant needs, then scores them."""

    def __init__(self) -> None:
        self.ms_rows: list[dict[str, float]] = []
        self.ms_outcomes: list[str] = []
        self.home_probs: list[float] = []
        self.home_outcomes: list[int] = []
        self.over25_probs: list[float] = []
        self.over25_outcomes: list[int] = []

    @property
    def sample_1x2(self) -> int:
        return len(self.ms_rows)

    @property
    def sample_over25(self) -> int:
        return len(self.over25_probs)

    def add(self, probs: dict, *, outcome: str, over25: int) -> None:
        ms = probs.get("MS")
        if ms and all(key in ms for key in ("home", "draw", "away")):
            self.ms_rows.append({key: float(ms[key]) for key in ("home", "draw", "away")})
            self.ms_outcomes.append(outcome)
            self.home_probs.append(float(ms["home"]))
            self.home_outcomes.append(1 if outcome == "home" else 0)
        au = probs.get("AU_2_5")
        if au and "over" in au:
            self.over25_probs.append(float(au["over"]))
            self.over25_outcomes.append(over25)

    def summarize(self) -> dict:
        summary: dict = {}
        if self.ms_rows:
            summary["brier_1x2"] = round(
                multiclass_brier(self.ms_rows, self.ms_outcomes), 6
            )
            summary["log_loss_home"] = round(
                log_loss(self.home_probs, self.home_outcomes), 6
            )
            summary["ece_home"] = round(
                expected_calibration_error(self.home_probs, self.home_outcomes), 6
            )
            summary["reliability_home"] = [
                {
                    "lower": bin_.lower,
                    "upper": bin_.upper,
                    "count": bin_.count,
                    "mean_predicted": round(bin_.mean_predicted, 4),
                    "observed_rate": round(bin_.observed_rate, 4),
                }
                for bin_ in reliability_bins(self.home_probs, self.home_outcomes)
                if bin_.count > 0
            ]
        if self.over25_probs:
            summary["log_loss_over25"] = round(
                log_loss(self.over25_probs, self.over25_outcomes), 6
            )
            summary["ece_over25"] = round(
                expected_calibration_error(self.over25_probs, self.over25_outcomes), 6
            )
        return summary
