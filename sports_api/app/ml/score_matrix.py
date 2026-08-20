"""Score probability matrix from Dixon-Coles rates."""

from __future__ import annotations

import math

from app.ml.dixon_coles import dixon_coles_tau

DEFAULT_MAX_GOALS = 10


def poisson_pmf(k: int, rate: float) -> float:
    if rate <= 0:
        return 1.0 if k == 0 else 0.0
    return math.exp(-rate) * rate**k / math.factorial(k)


def score_matrix(
    lambda_home: float,
    lambda_away: float,
    rho: float = 0.0,
    max_goals: int = DEFAULT_MAX_GOALS,
) -> list[list[float]]:
    """P(home=i, away=j) for i,j in [0, max_goals], normalized to sum 1.

    Applies the Dixon-Coles tau correction to the four low-score cells.
    """
    matrix: list[list[float]] = []
    total = 0.0
    for i in range(max_goals + 1):
        row: list[float] = []
        p_home = poisson_pmf(i, lambda_home)
        for j in range(max_goals + 1):
            probability = p_home * poisson_pmf(j, lambda_away)
            if i <= 1 and j <= 1:
                probability *= max(0.0, dixon_coles_tau(i, j, lambda_home, lambda_away, rho))
            row.append(probability)
            total += probability
        matrix.append(row)

    if total <= 0:
        raise ValueError("Degenerate score matrix; check the rates.")
    return [[probability / total for probability in row] for row in matrix]
