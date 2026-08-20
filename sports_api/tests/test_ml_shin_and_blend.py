import pytest

from app.ml.backtest import SettledBet, compare_stakings, simulate_bets
from app.ml.market_blend import BlendResult, blend_markets, blend_probabilities
from app.ml.value_detection import find_value_picks
from app.services.feature_math import (
    normalize_implied_probabilities,
    shin_probabilities,
)

# ---------------------------------------------------------------------------
# Shin de-vigging
# ---------------------------------------------------------------------------


def test_shin_sums_to_one_and_corrects_longshot_bias() -> None:
    odds = [1.20, 4.50]
    proportional = normalize_implied_probabilities(odds)
    shin = shin_probabilities(odds)

    assert sum(shin) == pytest.approx(1.0, abs=1e-9)
    # Shin loads the margin onto the longshot: favourite up, longshot down.
    assert shin[0] > proportional[0]
    assert shin[1] < proportional[1]


def test_shin_three_way_market() -> None:
    odds = [1.50, 4.20, 6.00]
    proportional = normalize_implied_probabilities(odds)
    shin = shin_probabilities(odds)

    assert sum(shin) == pytest.approx(1.0, abs=1e-9)
    assert shin[0] > proportional[0]
    assert shin[2] < proportional[2]


def test_shin_margin_free_book_matches_proportional() -> None:
    odds = [2.0, 2.0]
    assert shin_probabilities(odds) == pytest.approx([0.5, 0.5])


def test_shin_keeps_invalid_entries_in_place() -> None:
    result = shin_probabilities([1.5, None, 4.8])
    assert result[1] is None
    assert sum(value for value in result if value is not None) == pytest.approx(1.0)


def test_shin_single_valid_odds_falls_back_to_proportional() -> None:
    assert shin_probabilities([2.0, None]) == [1.0, None]


# ---------------------------------------------------------------------------
# Logit-space market blending
# ---------------------------------------------------------------------------


def test_blend_weight_extremes_recover_inputs() -> None:
    model = {"home": 0.55, "draw": 0.25, "away": 0.20}
    market = {"home": 0.45, "draw": 0.30, "away": 0.25}

    pure_model = blend_probabilities(model, market, model_weight=1.0)
    pure_market = blend_probabilities(model, market, model_weight=0.0)
    for key in model:
        assert pure_model[key] == pytest.approx(model[key], abs=1e-6)
        assert pure_market[key] == pytest.approx(market[key], abs=1e-6)

    halfway = blend_probabilities(model, market, model_weight=0.5)
    assert sum(halfway.values()) == pytest.approx(1.0)
    for key in model:
        low, high = sorted((model[key], market[key]))
        assert low - 1e-6 <= halfway[key] <= high + 1e-6


def test_blend_validates_inputs() -> None:
    with pytest.raises(ValueError):
        blend_probabilities({"a": 0.5}, {"a": 0.5}, model_weight=1.5)
    with pytest.raises(ValueError):
        blend_probabilities({"a": 1.0}, {"b": 1.0})


def test_blend_markets_requires_full_coverage() -> None:
    model = {
        "MS": {"home": 0.50, "draw": 0.28, "away": 0.22},
        "KG": {"yes": 0.58, "no": 0.42},
    }
    offered = {
        "MS": {"home": 2.05, "draw": 3.30},  # away missing -> passthrough
        "KG": {"yes": 1.75, "no": 2.10},
    }
    result = blend_markets(model, offered, model_weight=0.5)

    assert isinstance(result, BlendResult)
    assert result.blended_markets == ["KG"]
    assert result.probs["MS"] == model["MS"]
    assert "MS" not in result.market_probs
    assert sum(result.probs["KG"].values()) == pytest.approx(1.0)
    assert sum(result.market_probs["KG"].values()) == pytest.approx(1.0)


def test_full_market_blend_removes_margin_value() -> None:
    """With weight 0 the blended probability is the de-vigged market view;
    no selection can clear the margin, so value detection stays silent."""
    model = {"MS": {"home": 0.60, "draw": 0.25, "away": 0.15}}
    offered = {"MS": {"home": 1.85, "draw": 3.60, "away": 4.80}}
    result = blend_markets(model, offered, model_weight=0.0)

    assert result.blended_markets == ["MS"]
    assert find_value_picks(result.probs, offered) == []


# ---------------------------------------------------------------------------
# Backtest simulation core
# ---------------------------------------------------------------------------


def test_simulate_bets_flat_staking_profit_and_roi() -> None:
    bets = [
        SettledBet(probability=0.60, odds_decimal=2.0, won=True),
        SettledBet(probability=0.60, odds_decimal=2.0, won=False),
        SettledBet(probability=0.60, odds_decimal=2.0, won=True),
    ]
    report = simulate_bets(bets, starting_bankroll=100.0, flat_stake=10.0)

    assert report.n_bets == 3
    assert report.total_staked == pytest.approx(30.0)
    assert report.profit == pytest.approx(10.0)
    assert report.roi == pytest.approx(10.0 / 30.0)
    assert report.hit_rate == pytest.approx(2 / 3)
    assert report.final_bankroll == pytest.approx(110.0)


def test_simulate_bets_kelly_skips_edgeless_and_tracks_drawdown() -> None:
    bets = [
        SettledBet(probability=0.40, odds_decimal=2.0, won=True),  # no edge -> skip
        SettledBet(probability=0.60, odds_decimal=2.0, won=False),
        SettledBet(probability=0.60, odds_decimal=2.0, won=True),
    ]
    report = simulate_bets(bets, starting_bankroll=100.0)

    assert report.n_skipped == 1
    assert report.n_bets == 2
    # Quarter Kelly at p=0.6, odds 2.0 -> 5% of bankroll per bet.
    assert report.max_drawdown == pytest.approx(0.05)
    assert report.final_bankroll == pytest.approx(99.75)


def test_simulate_bets_validates_inputs() -> None:
    with pytest.raises(ValueError):
        simulate_bets([], starting_bankroll=0.0)
    with pytest.raises(ValueError):
        simulate_bets([], flat_stake=-1.0)


def test_compare_stakings_returns_both_reports() -> None:
    bets = [SettledBet(probability=0.60, odds_decimal=2.0, won=True)]
    reports = compare_stakings(bets)
    assert set(reports) == {"kelly", "flat"}
    assert reports["kelly"].n_bets == 1
    assert reports["flat"].n_bets == 1
