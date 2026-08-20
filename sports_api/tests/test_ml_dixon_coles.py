import math
import random
from datetime import date, timedelta

import pytest

from app.ml.dixon_coles import (
    DixonColesParams,
    MatchResult,
    dixon_coles_tau,
    fit_dixon_coles,
    time_decay_weight,
)
from app.ml.market_derivations import derive_iddaa_markets
from app.ml.score_matrix import poisson_pmf, score_matrix

TEAMS = ["strong", "mid_a", "mid_b", "weak"]
TRUE_ATTACK = {"strong": 0.45, "mid_a": 0.05, "mid_b": -0.05, "weak": -0.45}
TRUE_DEFENSE = {"strong": 0.35, "mid_a": 0.05, "mid_b": -0.05, "weak": -0.35}
TRUE_MU = math.log(1.25)
TRUE_HA = 0.30


def synthetic_matches(rounds: int, seed: int = 7) -> list[MatchResult]:
    rng = random.Random(seed)
    matches: list[MatchResult] = []
    start = date(2025, 8, 1)
    day = 0
    for _ in range(rounds):
        for home in TEAMS:
            for away in TEAMS:
                if home == away:
                    continue
                lambda_home = math.exp(
                    TRUE_MU + TRUE_HA + TRUE_ATTACK[home] - TRUE_DEFENSE[away]
                )
                lambda_away = math.exp(TRUE_MU + TRUE_ATTACK[away] - TRUE_DEFENSE[home])
                matches.append(
                    MatchResult(
                        home_team=home,
                        away_team=away,
                        home_goals=_poisson_sample(rng, lambda_home),
                        away_goals=_poisson_sample(rng, lambda_away),
                        played_at=start + timedelta(days=day),
                    )
                )
                day += 1
    return matches


def _poisson_sample(rng: random.Random, rate: float) -> int:
    threshold = math.exp(-rate)
    k = 0
    product = rng.random()
    while product > threshold:
        product *= rng.random()
        k += 1
    return k


def test_fit_recovers_team_ordering_and_home_advantage() -> None:
    matches = synthetic_matches(rounds=60)
    params = fit_dixon_coles(matches, halflife_days=10_000.0)

    assert params.attack["strong"] > params.attack["mid_a"] > params.attack["weak"]
    assert params.defense["strong"] > params.defense["weak"]
    assert 0.1 < params.home_advantage < 0.5
    # Attack estimates should land near the true values.
    assert params.attack["strong"] == pytest.approx(TRUE_ATTACK["strong"], abs=0.15)
    assert params.attack["weak"] == pytest.approx(TRUE_ATTACK["weak"], abs=0.15)


def test_fit_rates_reproduce_expected_goals() -> None:
    matches = synthetic_matches(rounds=60)
    params = fit_dixon_coles(matches, halflife_days=10_000.0)
    lambda_home, lambda_away = params.rates("strong", "weak")
    true_home = math.exp(TRUE_MU + TRUE_HA + TRUE_ATTACK["strong"] - TRUE_DEFENSE["weak"])
    true_away = math.exp(TRUE_MU + TRUE_ATTACK["weak"] - TRUE_DEFENSE["strong"])
    assert lambda_home == pytest.approx(true_home, rel=0.2)
    assert lambda_away == pytest.approx(true_away, rel=0.25)
    assert lambda_home > lambda_away


def test_fit_requires_minimum_history() -> None:
    matches = synthetic_matches(rounds=1)[:10]
    with pytest.raises(ValueError, match="at least"):
        fit_dixon_coles(matches)


def test_unseen_team_falls_back_to_league_average() -> None:
    params = DixonColesParams(
        mu=TRUE_MU, home_advantage=TRUE_HA, rho=0.0, attack={"a": 0.3}, defense={"a": 0.2}
    )
    lambda_home, lambda_away = params.rates("unknown-1", "unknown-2")
    assert lambda_home == pytest.approx(math.exp(TRUE_MU + TRUE_HA))
    assert lambda_away == pytest.approx(math.exp(TRUE_MU))
    assert not params.knows_team("unknown-1")


def test_params_round_trip_serialization() -> None:
    matches = synthetic_matches(rounds=10)
    params = fit_dixon_coles(matches)
    restored = DixonColesParams.from_dict(params.to_dict())
    assert restored.rates("strong", "weak") == params.rates("strong", "weak")
    assert restored.rho == params.rho


def test_time_decay_weight_halves_at_halflife() -> None:
    reference = date(2026, 7, 10)
    assert time_decay_weight(reference, reference, 180.0) == pytest.approx(1.0)
    old = reference - timedelta(days=180)
    assert time_decay_weight(old, reference, 180.0) == pytest.approx(0.5)


def test_dixon_coles_tau_shifts_low_scores() -> None:
    # Negative rho lifts the draw-ish corrections
    assert dixon_coles_tau(0, 0, 1.5, 1.1, -0.05) > 1.0
    assert dixon_coles_tau(1, 1, 1.5, 1.1, -0.05) > 1.0
    assert dixon_coles_tau(1, 0, 1.5, 1.1, -0.05) < 1.0
    assert dixon_coles_tau(3, 2, 1.5, 1.1, -0.05) == 1.0


def test_score_matrix_is_normalized_probability_distribution() -> None:
    matrix = score_matrix(1.6, 1.2, rho=-0.05)
    total = sum(sum(row) for row in matrix)
    assert total == pytest.approx(1.0)
    assert all(probability >= 0 for row in matrix for probability in row)


def test_poisson_pmf_sums_to_one() -> None:
    assert sum(poisson_pmf(k, 1.7) for k in range(60)) == pytest.approx(1.0)


def test_negative_rho_increases_draw_probability() -> None:
    base = score_matrix(1.4, 1.1, rho=0.0)
    corrected = score_matrix(1.4, 1.1, rho=-0.08)

    def draw_probability(matrix):
        return sum(matrix[i][i] for i in range(len(matrix)))

    assert draw_probability(corrected) > draw_probability(base)


def test_derive_iddaa_markets_probabilities_are_consistent() -> None:
    markets = derive_iddaa_markets(1.55, 1.10, rho=-0.04)

    for code in ("MS", "AU_2_5", "KG", "IY", "IY_MS", "TG", "H_MS_1", "IY_AU_0_5"):
        assert code in markets
        total = sum(markets[code].values())
        assert total == pytest.approx(1.0, abs=1e-6), code

    ms = markets["MS"]
    cs = markets["CS"]
    assert cs["home_draw"] == pytest.approx(ms["home"] + ms["draw"])

    # More expected goals for home team -> home more likely than away.
    assert ms["home"] > ms["away"]

    # Over 1.5 must dominate over 2.5 which dominates over 3.5.
    assert (
        markets["AU_1_5"]["over"]
        > markets["AU_2_5"]["over"]
        > markets["AU_3_5"]["over"]
    )

    # HT/FT marginal over full-time result must approximate MS.
    ht_ft = markets["IY_MS"]
    ft_home = ht_ft["home_home"] + ht_ft["draw_home"] + ht_ft["away_home"]
    assert ft_home == pytest.approx(ms["home"], abs=0.03)

    # First-half goals are a subset of the match: over 0.5 in H1 < over 0.5 overall.
    assert markets["IY_AU_1_5"]["over"] < markets["AU_1_5"]["over"]

    # Handicap +1 for home makes "home" outcome more likely than raw MS.
    assert markets["H_MS_1"]["home"] > ms["home"]
    assert markets["H_MS_MINUS_1"]["home"] < ms["home"]
