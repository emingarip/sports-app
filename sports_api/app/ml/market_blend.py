"""Blend model probabilities with de-vigged market probabilities.

Closing odds are near-efficient: a standalone model rarely beats the market
long-term. Blending the Dixon-Coles probability with the Shin de-vigged market
probability in logit space improves calibration and damps overconfident EV
flags (roadmap 2.5, ADR 10). ``DEFAULT_MODEL_WEIGHT`` is an even blend until
the walk-forward backtest learns a better weight.
"""

from __future__ import annotations

import math
from collections.abc import Mapping
from dataclasses import dataclass, field

from app.services.feature_math import shin_probabilities

DEFAULT_MODEL_WEIGHT = 0.5
"""Share of the logit blend given to the model (rest goes to the market)."""

_EPS = 1e-6


def _logit(probability: float) -> float:
    clamped = min(max(probability, _EPS), 1.0 - _EPS)
    return math.log(clamped / (1.0 - clamped))


def _inverse_logit(value: float) -> float:
    return 1.0 / (1.0 + math.exp(-value))


def blend_probabilities(
    model_probs: Mapping[str, float],
    market_probs: Mapping[str, float],
    *,
    model_weight: float = DEFAULT_MODEL_WEIGHT,
) -> dict[str, float]:
    """Logit-space blend per selection, renormalised to sum to 1.

    Both mappings must cover the same selection keys; ``model_weight`` is the
    model's share in [0, 1] (0 = trust the market fully, 1 = pure model).
    """
    if not 0.0 <= model_weight <= 1.0:
        raise ValueError(f"model_weight must be within [0, 1], got {model_weight}")
    if set(model_probs) != set(market_probs):
        raise ValueError("model and market probabilities must cover the same selections")
    blended = {
        selection: _inverse_logit(
            model_weight * _logit(model_probs[selection])
            + (1.0 - model_weight) * _logit(market_probs[selection])
        )
        for selection in model_probs
    }
    total = sum(blended.values())
    return {selection: value / total for selection, value in blended.items()}


@dataclass(slots=True)
class BlendResult:
    """Blended market probabilities plus the market view used to build them."""

    probs: dict[str, dict[str, float]]
    market_probs: dict[str, dict[str, float]] = field(default_factory=dict)
    blended_markets: list[str] = field(default_factory=list)


def blend_markets(
    model_markets: Mapping[str, Mapping[str, float]],
    offered_odds: Mapping[str, Mapping[str, float]],
    *,
    model_weight: float = DEFAULT_MODEL_WEIGHT,
) -> BlendResult:
    """Blend every market where the bulletin covers the full selection set.

    Shin de-vigging needs the complete market to estimate the margin, so a
    market with missing or suspended selections is passed through as pure
    model probabilities and left out of ``blended_markets``.
    """
    result = BlendResult(probs={})
    for market_code, selections in model_markets.items():
        model = dict(selections)
        odds = offered_odds.get(market_code)
        if (
            odds is None
            or set(odds) != set(model)
            or any(value is None or value <= 1.0 for value in odds.values())
        ):
            result.probs[market_code] = model
            continue
        ordered_keys = list(model)
        shin = shin_probabilities([odds[key] for key in ordered_keys])
        if any(value is None for value in shin):
            result.probs[market_code] = model
            continue
        market = dict(zip(ordered_keys, shin, strict=True))
        result.market_probs[market_code] = market
        result.probs[market_code] = blend_probabilities(
            model, market, model_weight=model_weight
        )
        result.blended_markets.append(market_code)
    return result
