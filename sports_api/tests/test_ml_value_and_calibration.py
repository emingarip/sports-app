import pytest

from app.ml.calibration import (
    brier_score,
    expected_calibration_error,
    log_loss,
    multiclass_brier,
    reliability_bins,
)
from app.ml.value_detection import (
    expected_value,
    find_value_picks,
    kelly_fraction,
)


def test_expected_value_basic() -> None:
    assert expected_value(0.5, 2.0) == pytest.approx(0.0)
    assert expected_value(0.55, 2.0) == pytest.approx(0.10)
    assert expected_value(0.40, 2.0) == pytest.approx(-0.20)


def test_kelly_fraction_positive_edge_only() -> None:
    # p=0.55 at odds 2.0: full Kelly = 0.10, quarter Kelly = 0.025
    assert kelly_fraction(0.55, 2.0) == pytest.approx(0.025)
    # No edge -> no stake.
    assert kelly_fraction(0.50, 2.0) == 0.0
    assert kelly_fraction(0.30, 1.5) == 0.0
    assert kelly_fraction(0.9, 1.0) == 0.0


def test_find_value_picks_filters_and_sorts() -> None:
    model = {
        "MS": {"home": 0.50, "draw": 0.27, "away": 0.23},
        "KG": {"yes": 0.60, "no": 0.40},
        "AU_2_5": {"over": 0.05, "under": 0.95},
    }
    odds = {
        "MS": {"home": 2.30, "draw": 3.40, "away": 3.10},  # home EV = 0.15
        "KG": {"yes": 1.80, "no": 2.05},  # yes EV = 0.08
        "AU_2_5": {"over": 30.0},  # huge EV but model prob below min threshold
    }
    picks = find_value_picks(model, odds)

    assert [(pick.market_code, pick.selection_key) for pick in picks] == [
        ("MS", "home"),
        ("KG", "yes"),
    ]
    best = picks[0]
    assert best.expected_value == pytest.approx(0.15)
    assert best.implied_probability == pytest.approx(1 / 2.30)
    assert best.kelly_stake > 0


def test_find_value_picks_empty_when_no_edge() -> None:
    model = {"MS": {"home": 0.40, "draw": 0.30, "away": 0.30}}
    odds = {"MS": {"home": 2.20, "draw": 3.10, "away": 3.10}}
    assert find_value_picks(model, odds) == []


def test_brier_and_log_loss_reward_better_forecasts() -> None:
    outcomes = [1, 0, 1, 1, 0]
    good = [0.8, 0.2, 0.7, 0.9, 0.1]
    bad = [0.5, 0.5, 0.5, 0.5, 0.5]
    assert brier_score(good, outcomes) < brier_score(bad, outcomes)
    assert log_loss(good, outcomes) < log_loss(bad, outcomes)


def test_multiclass_brier_perfect_forecast_is_zero() -> None:
    rows = [{"home": 1.0, "draw": 0.0, "away": 0.0}]
    assert multiclass_brier(rows, ["home"]) == pytest.approx(0.0)


def test_reliability_bins_capture_observed_rates() -> None:
    probabilities = [0.15] * 50 + [0.85] * 50
    outcomes = [0] * 45 + [1] * 5 + [1] * 42 + [0] * 8
    bins = reliability_bins(probabilities, outcomes, n_bins=10)

    low_bin = bins[1]
    assert low_bin.count == 50
    assert low_bin.mean_predicted == pytest.approx(0.15)
    assert low_bin.observed_rate == pytest.approx(0.10)

    high_bin = bins[8]
    assert high_bin.count == 50
    assert high_bin.observed_rate == pytest.approx(0.84)

    ece = expected_calibration_error(probabilities, outcomes, n_bins=10)
    assert 0.0 < ece < 0.06


def test_metric_input_validation() -> None:
    with pytest.raises(ValueError):
        brier_score([], [])
    with pytest.raises(ValueError):
        log_loss([0.5], [1, 0])
