"""Tests for the settlement + CLV layer added with the backtest wiring.

`app/ml/backtest.py` had been written but never called by any service, so the
question "does the model make money" was unanswerable. These cover the pure
pieces that answer it: which selections a final score settles, and how closing
line value is summarised.
"""

from __future__ import annotations

import math

import pytest

from app.services.prediction_service import _clv_summary, _outcome_for_selection


@pytest.mark.parametrize(
    ("market", "selection", "home", "away", "expected"),
    [
        ("MS", "home", 2, 1, True),
        ("MS", "draw", 2, 1, False),
        ("MS", "draw", 1, 1, True),
        ("MS", "away", 0, 3, True),
        ("CS", "home_draw", 1, 1, True),
        ("CS", "home_draw", 0, 1, False),
        ("CS", "home_away", 1, 1, False),
        ("CS", "draw_away", 0, 1, True),
        ("AU_2_5", "over", 2, 1, True),
        ("AU_2_5", "under", 2, 1, False),
        ("AU_1_5", "under", 1, 0, True),
        ("AU_3_5", "over", 2, 2, True),
        ("KG", "yes", 1, 1, True),
        ("KG", "yes", 3, 0, False),
        ("KG", "no", 3, 0, True),
        ("TG", "0_1", 1, 0, True),
        ("TG", "2_3", 2, 1, True),
        ("TG", "4_5", 3, 2, True),
        ("TG", "6_plus", 4, 3, True),
        # European handicap: home +1 vs away.
        ("H_MS_1", "home", 0, 0, True),
        ("H_MS_1", "draw", 0, 1, True),
        ("H_MS_1", "away", 0, 2, True),
        ("H_MS_MINUS_1", "draw", 1, 0, True),
        ("H_MS_MINUS_1", "home", 2, 0, True),
    ],
)
def test_outcome_for_selection(market, selection, home, away, expected) -> None:
    assert _outcome_for_selection(market, selection, home, away) is expected


@pytest.mark.parametrize("market", ["IY", "IY_AU_0_5", "IY_AU_1_5", "IY_MS"])
def test_half_time_markets_are_not_settled_from_a_full_time_score(market) -> None:
    # These need the half-time score; guessing from the final score would
    # poison the very metrics this module produces.
    assert _outcome_for_selection(market, "home", 2, 1) is None


def test_unknown_market_returns_none_rather_than_guessing() -> None:
    assert _outcome_for_selection("CORNERS_9_5", "over", 3, 1) is None


def test_clv_summary_is_empty_without_closing_prices() -> None:
    settled = [{"taken_odds": 2.0, "closing_odds": None}]
    assert _clv_summary(settled) == {
        "clv_sample": 0,
        "mean_clv": None,
        "clv_positive_rate": None,
    }


def test_clv_summary_rewards_beating_the_close() -> None:
    settled = [
        {"taken_odds": 2.10, "closing_odds": 2.00},  # price shortened -> +CLV
        {"taken_odds": 1.90, "closing_odds": 2.00},  # price drifted   -> -CLV
        {"taken_odds": 2.20, "closing_odds": 2.00},
    ]
    summary = _clv_summary(settled)
    assert summary["clv_sample"] == 3
    assert summary["clv_positive_rate"] == pytest.approx(2 / 3, abs=1e-6)
    expected = (
        math.log(2.10 / 2.00) + math.log(1.90 / 2.00) + math.log(2.20 / 2.00)
    ) / 3
    assert summary["mean_clv"] == pytest.approx(expected, abs=1e-6)


def test_clv_is_symmetric_in_log_space() -> None:
    """A 2.00 -> 1.80 move must mirror 1.80 -> 2.00.

    Plain percentage differences are not symmetric, which would bias the
    average toward whichever direction happened to be larger.
    """
    shortened = _clv_summary([{"taken_odds": 2.00, "closing_odds": 1.80}])
    drifted = _clv_summary([{"taken_odds": 1.80, "closing_odds": 2.00}])
    assert shortened["mean_clv"] == pytest.approx(-drifted["mean_clv"], abs=1e-9)
