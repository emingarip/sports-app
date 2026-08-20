"""Time-weighted Dixon-Coles goal model.

The canonical score model of the platform: per-team attack/defence strengths,
home advantage and the Dixon-Coles low-score correction (rho), fitted on
historical results with exponential time decay. All markets are derived from
the score distribution this model produces (see ``market_derivations``), so
every probability shown to a user comes from one consistent source.

Implementation notes:
- Pure Python (no numpy/scipy) so it runs everywhere the API runs.
- Rates are fitted by weighted Poisson maximum likelihood via gradient ascent
  (closed-form gradients); ``rho`` is then profiled with a 1-D grid search on
  the full Dixon-Coles likelihood. This two-stage scheme is a standard
  practical approximation and keeps the optimizer dependency-free.
- Identifiability: attack and defence ratings are re-centered to mean zero
  after every step.
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass, field
from datetime import date, datetime

logger = logging.getLogger(__name__)


@dataclass(slots=True)
class MatchResult:
    home_team: str
    away_team: str
    home_goals: int
    away_goals: int
    played_at: date


@dataclass(slots=True)
class DixonColesParams:
    mu: float
    """League-wide log of expected away-team goals."""

    home_advantage: float
    rho: float
    attack: dict[str, float] = field(default_factory=dict)
    defense: dict[str, float] = field(default_factory=dict)
    trained_matches: int = 0
    trained_at: str | None = None
    converged: bool = False
    iterations_run: int = 0
    final_gradient_norm: float = math.inf

    def rates(self, home_team: str, away_team: str) -> tuple[float, float]:
        """Expected goals (lambda_home, lambda_away); unseen teams get league average."""
        attack_home = self.attack.get(home_team, 0.0)
        attack_away = self.attack.get(away_team, 0.0)
        defense_home = self.defense.get(home_team, 0.0)
        defense_away = self.defense.get(away_team, 0.0)
        lambda_home = math.exp(self.mu + self.home_advantage + attack_home - defense_away)
        lambda_away = math.exp(self.mu + attack_away - defense_home)
        return lambda_home, lambda_away

    def knows_team(self, team: str) -> bool:
        return team in self.attack

    def to_dict(self) -> dict:
        return {
            "mu": self.mu,
            "home_advantage": self.home_advantage,
            "rho": self.rho,
            "attack": dict(self.attack),
            "defense": dict(self.defense),
            "trained_matches": self.trained_matches,
            "trained_at": self.trained_at,
            "converged": self.converged,
            "iterations_run": self.iterations_run,
        }

    @classmethod
    def from_dict(cls, payload: dict) -> DixonColesParams:
        return cls(
            mu=float(payload["mu"]),
            home_advantage=float(payload["home_advantage"]),
            rho=float(payload["rho"]),
            attack={str(k): float(v) for k, v in payload.get("attack", {}).items()},
            defense={str(k): float(v) for k, v in payload.get("defense", {}).items()},
            trained_matches=int(payload.get("trained_matches", 0)),
            trained_at=payload.get("trained_at"),
            converged=bool(payload.get("converged", False)),
            iterations_run=int(payload.get("iterations_run", 0)),
        )


def dixon_coles_tau(
    home_goals: int,
    away_goals: int,
    lambda_home: float,
    lambda_away: float,
    rho: float,
) -> float:
    """Low-score dependence correction from Dixon & Coles (1997)."""
    if home_goals == 0 and away_goals == 0:
        return 1.0 - lambda_home * lambda_away * rho
    if home_goals == 0 and away_goals == 1:
        return 1.0 + lambda_home * rho
    if home_goals == 1 and away_goals == 0:
        return 1.0 + lambda_away * rho
    if home_goals == 1 and away_goals == 1:
        return 1.0 - rho
    return 1.0


def time_decay_weight(played_at: date, reference: date, halflife_days: float) -> float:
    """Exponential decay: a match ``halflife_days`` old counts half as much."""
    age_days = max(0.0, float((reference - played_at).days))
    return 0.5 ** (age_days / halflife_days)


def fit_dixon_coles(
    matches: list[MatchResult],
    *,
    reference_date: date | None = None,
    halflife_days: float = 180.0,
    iterations: int = 400,
    learning_rate: float = 0.02,
    l2: float = 0.001,
    min_matches: int = 30,
    gradient_tolerance: float = 1e-6,
) -> DixonColesParams:
    """Fit the model on historical results.

    Raises ``ValueError`` when there is not enough history to produce a
    meaningful fit — callers should treat that as "no model available".
    """
    if len(matches) < min_matches:
        raise ValueError(
            f"Need at least {min_matches} matches to fit Dixon-Coles, got {len(matches)}."
        )
    if reference_date is None:
        reference_date = max(match.played_at for match in matches)

    teams = sorted({m.home_team for m in matches} | {m.away_team for m in matches})
    attack = {team: 0.0 for team in teams}
    defense = {team: 0.0 for team in teams}

    weights = [
        time_decay_weight(match.played_at, reference_date, halflife_days) for match in matches
    ]
    total_weight = sum(weights)
    if total_weight <= 0:
        raise ValueError("All match weights are zero; check reference date / halflife.")

    weighted_goals = sum(
        weight * (match.home_goals + match.away_goals)
        for match, weight in zip(matches, weights, strict=True)
    )
    # Initialize mu at the weighted average goals per team per match.
    mu = math.log(max(0.25, weighted_goals / (2.0 * total_weight)))
    home_advantage = 0.25

    completed_iterations = 0
    converged = False
    gradient_norm = math.inf
    for _ in range(iterations):
        completed_iterations += 1
        grad_attack = {team: 0.0 for team in teams}
        grad_defense = {team: 0.0 for team in teams}
        grad_mu = 0.0
        grad_ha = 0.0

        for match, weight in zip(matches, weights, strict=True):
            lambda_home = math.exp(
                mu + home_advantage + attack[match.home_team] - defense[match.away_team]
            )
            lambda_away = math.exp(mu + attack[match.away_team] - defense[match.home_team])
            # d/d(log lambda) of Poisson log-likelihood = k - lambda
            residual_home = weight * (match.home_goals - lambda_home)
            residual_away = weight * (match.away_goals - lambda_away)

            grad_attack[match.home_team] += residual_home
            grad_defense[match.away_team] -= residual_home
            grad_attack[match.away_team] += residual_away
            grad_defense[match.home_team] -= residual_away
            grad_mu += residual_home + residual_away
            grad_ha += residual_home

        scale = learning_rate / total_weight
        for team in teams:
            attack[team] += scale * (grad_attack[team] - l2 * attack[team] * total_weight)
            defense[team] += scale * (grad_defense[team] - l2 * defense[team] * total_weight)
        mu += scale * grad_mu
        home_advantage += scale * grad_ha

        # Re-center for identifiability.
        attack_mean = sum(attack.values()) / len(teams)
        defense_mean = sum(defense.values()) / len(teams)
        for team in teams:
            attack[team] -= attack_mean
            defense[team] -= defense_mean
        mu += attack_mean - defense_mean

        # Convergence check. Previously the loop always ran the full
        # ``iterations`` and the caller had no way to know whether the fit had
        # settled or simply run out of budget - a badly conditioned league
        # would publish ratings from a half-finished optimisation.
        gradient_norm = math.sqrt(
            grad_mu**2
            + grad_ha**2
            + sum(value**2 for value in grad_attack.values())
            + sum(value**2 for value in grad_defense.values())
        ) / total_weight
        if gradient_norm < gradient_tolerance:
            converged = True
            break

    if not converged:
        logger.warning(
            "Dixon-Coles did not converge in %s iterations "
            "(gradient norm %.3e > tolerance %.1e, %s matches, %s teams)",
            completed_iterations,
            gradient_norm,
            gradient_tolerance,
            len(matches),
            len(teams),
        )

    params = DixonColesParams(
        mu=mu,
        home_advantage=home_advantage,
        rho=0.0,
        attack=attack,
        defense=defense,
        trained_matches=len(matches),
        trained_at=datetime.now().isoformat(timespec="seconds"),
        converged=converged,
        iterations_run=completed_iterations,
        final_gradient_norm=gradient_norm,
    )
    params.rho = _profile_rho(matches, weights, params)
    return params


def _profile_rho(
    matches: list[MatchResult],
    weights: list[float],
    params: DixonColesParams,
) -> float:
    """1-D grid search for rho on the full Dixon-Coles likelihood."""
    best_rho = 0.0
    best_ll = -math.inf
    for step in range(-30, 31):
        rho = step / 200.0  # [-0.15, 0.15]
        ll = 0.0
        valid = True
        for match, weight in zip(matches, weights, strict=True):
            lambda_home, lambda_away = params.rates(match.home_team, match.away_team)
            tau = dixon_coles_tau(
                match.home_goals, match.away_goals, lambda_home, lambda_away, rho
            )
            if tau <= 0:
                valid = False
                break
            ll += weight * math.log(tau)
        if valid and ll > best_ll:
            best_ll = ll
            best_rho = rho
    return best_rho
