"""Derive iddaa market probabilities from a score distribution.

Every market probability comes from the same score matrix (single-source
consistency — design principle 0.1.3 in the roadmap document). Keys follow the
canonical taxonomy in :mod:`app.domain.iddaa_markets`: the result is a mapping
``market_code -> {selection_key: probability}`` covering all iddaa v1 markets.

Half-time markets use a half-split approximation: first-half goals are Poisson
with ``FIRST_HALF_GOAL_SHARE`` of the full-match rate, second half gets the
rest, halves independent. Empirically ~44-46% of goals fall before the break.
"""

from __future__ import annotations

from app.ml.score_matrix import DEFAULT_MAX_GOALS, poisson_pmf, score_matrix

FIRST_HALF_GOAL_SHARE = 0.45
_HALF_MAX_GOALS = 6


def result_probabilities(matrix: list[list[float]]) -> dict[str, float]:
    home = draw = away = 0.0
    for i, row in enumerate(matrix):
        for j, probability in enumerate(row):
            if i > j:
                home += probability
            elif i == j:
                draw += probability
            else:
                away += probability
    return {"home": home, "draw": draw, "away": away}


def totals_probabilities(matrix: list[list[float]], line: float) -> dict[str, float]:
    over = 0.0
    for i, row in enumerate(matrix):
        for j, probability in enumerate(row):
            if i + j > line:
                over += probability
    return {"over": over, "under": 1.0 - over}


def btts_probabilities(matrix: list[list[float]]) -> dict[str, float]:
    yes = 0.0
    for i, row in enumerate(matrix):
        for j, probability in enumerate(row):
            if i >= 1 and j >= 1:
                yes += probability
    return {"yes": yes, "no": 1.0 - yes}


def handicap_probabilities(matrix: list[list[float]], line: float) -> dict[str, float]:
    """European handicap: outcome of (home_goals + line) vs away_goals."""
    home = draw = away = 0.0
    for i, row in enumerate(matrix):
        for j, probability in enumerate(row):
            adjusted = i + line - j
            if adjusted > 1e-9:
                home += probability
            elif adjusted < -1e-9:
                away += probability
            else:
                draw += probability
    return {"home": home, "draw": draw, "away": away}


def goal_range_probabilities(matrix: list[list[float]]) -> dict[str, float]:
    ranges = {"0_1": 0.0, "2_3": 0.0, "4_5": 0.0, "6_plus": 0.0}
    for i, row in enumerate(matrix):
        for j, probability in enumerate(row):
            total = i + j
            if total <= 1:
                ranges["0_1"] += probability
            elif total <= 3:
                ranges["2_3"] += probability
            elif total <= 5:
                ranges["4_5"] += probability
            else:
                ranges["6_plus"] += probability
    return ranges


def _half_rates(lambda_home: float, lambda_away: float) -> tuple[float, float, float, float]:
    h1_home = lambda_home * FIRST_HALF_GOAL_SHARE
    h1_away = lambda_away * FIRST_HALF_GOAL_SHARE
    return h1_home, h1_away, lambda_home - h1_home, lambda_away - h1_away


def first_half_result_probabilities(
    lambda_home: float, lambda_away: float
) -> dict[str, float]:
    h1_home, h1_away, _, _ = _half_rates(lambda_home, lambda_away)
    half_matrix = score_matrix(h1_home, h1_away, 0.0, max_goals=_HALF_MAX_GOALS)
    return result_probabilities(half_matrix)


def first_half_totals_probabilities(
    lambda_home: float, lambda_away: float, line: float
) -> dict[str, float]:
    h1_home, h1_away, _, _ = _half_rates(lambda_home, lambda_away)
    half_matrix = score_matrix(h1_home, h1_away, 0.0, max_goals=_HALF_MAX_GOALS)
    return totals_probabilities(half_matrix, line)


def ht_ft_probabilities(lambda_home: float, lambda_away: float) -> dict[str, float]:
    """Joint half-time / full-time result from independent half distributions."""
    h1_home, h1_away, h2_home, h2_away = _half_rates(lambda_home, lambda_away)

    h1_home_pmf = [poisson_pmf(k, h1_home) for k in range(_HALF_MAX_GOALS + 1)]
    h1_away_pmf = [poisson_pmf(k, h1_away) for k in range(_HALF_MAX_GOALS + 1)]
    h2_home_pmf = [poisson_pmf(k, h2_home) for k in range(_HALF_MAX_GOALS + 1)]
    h2_away_pmf = [poisson_pmf(k, h2_away) for k in range(_HALF_MAX_GOALS + 1)]

    def sign(value: int) -> str:
        if value > 0:
            return "home"
        if value < 0:
            return "away"
        return "draw"

    joint: dict[str, float] = {
        f"{ht}_{ft}": 0.0
        for ht in ("home", "draw", "away")
        for ft in ("home", "draw", "away")
    }
    total = 0.0
    for h1 in range(_HALF_MAX_GOALS + 1):
        for a1 in range(_HALF_MAX_GOALS + 1):
            p_first = h1_home_pmf[h1] * h1_away_pmf[a1]
            if p_first <= 0:
                continue
            for h2 in range(_HALF_MAX_GOALS + 1):
                for a2 in range(_HALF_MAX_GOALS + 1):
                    probability = p_first * h2_home_pmf[h2] * h2_away_pmf[a2]
                    key = f"{sign(h1 - a1)}_{sign(h1 + h2 - a1 - a2)}"
                    joint[key] += probability
                    total += probability

    return {key: value / total for key, value in joint.items()}


def derive_iddaa_markets(
    lambda_home: float,
    lambda_away: float,
    rho: float = 0.0,
    max_goals: int = DEFAULT_MAX_GOALS,
) -> dict[str, dict[str, float]]:
    """All iddaa v1 market probabilities keyed by market code.

    Codes match :data:`app.domain.iddaa_markets.IDDAA_MARKETS`.
    """
    matrix = score_matrix(lambda_home, lambda_away, rho, max_goals=max_goals)
    result = result_probabilities(matrix)

    double_chance = {
        "home_draw": result["home"] + result["draw"],
        "home_away": result["home"] + result["away"],
        "draw_away": result["draw"] + result["away"],
    }

    return {
        "MS": result,
        "CS": double_chance,
        "AU_1_5": totals_probabilities(matrix, 1.5),
        "AU_2_5": totals_probabilities(matrix, 2.5),
        "AU_3_5": totals_probabilities(matrix, 3.5),
        "KG": btts_probabilities(matrix),
        "IY_MS": ht_ft_probabilities(lambda_home, lambda_away),
        "H_MS_1": handicap_probabilities(matrix, 1.0),
        "H_MS_MINUS_1": handicap_probabilities(matrix, -1.0),
        "IY": first_half_result_probabilities(lambda_home, lambda_away),
        "IY_AU_0_5": first_half_totals_probabilities(lambda_home, lambda_away, 0.5),
        "IY_AU_1_5": first_half_totals_probabilities(lambda_home, lambda_away, 1.5),
        "TG": goal_range_probabilities(matrix),
    }
