"""Convergence behaviour of the Dixon-Coles fit.

The optimiser used to run a fixed 400 iterations with no stopping rule, so a
badly conditioned league published ratings from a half-finished optimisation
and nothing in the output said so.
"""

from __future__ import annotations

import logging
from datetime import date

from app.ml.dixon_coles import MatchResult, fit_dixon_coles


def _history(n: int = 120) -> list[MatchResult]:
    teams = [f"t{i}" for i in range(8)]
    matches: list[MatchResult] = []
    for i in range(n):
        home = teams[i % len(teams)]
        away = teams[(i // len(teams) + 1) % len(teams)]
        if home == away:
            away = teams[(i + 3) % len(teams)]
        matches.append(
            MatchResult(
                home_team=home,
                away_team=away,
                home_goals=(i % 4),
                away_goals=((i + 1) % 3),
                played_at=date(2026, 1, 1 + (i % 28)),
            )
        )
    return matches


def test_fit_reports_convergence_metadata() -> None:
    params = fit_dixon_coles(_history())
    assert params.iterations_run > 0
    assert params.final_gradient_norm >= 0.0
    # to_dict feeds the API payload; the flag must survive the round trip.
    assert params.to_dict()["converged"] is params.converged


def test_early_exit_when_gradient_is_already_small() -> None:
    loose = fit_dixon_coles(_history(), gradient_tolerance=1.0)
    tight = fit_dixon_coles(_history(), gradient_tolerance=1e-12)
    assert loose.converged is True
    assert loose.iterations_run < tight.iterations_run


def test_non_convergence_is_logged_rather_than_silent(caplog) -> None:
    with caplog.at_level(logging.WARNING, logger="app.ml.dixon_coles"):
        params = fit_dixon_coles(
            _history(), iterations=3, gradient_tolerance=1e-12
        )
    assert params.converged is False
    assert any("did not converge" in record.message for record in caplog.records)
