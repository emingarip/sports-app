"""Value (+EV) detection and stake sizing.

The scientific core of the product: a pick is only worth playing when the
model's probability beats the bookmaker's implied probability by a margin
(roadmap principle 0.1.2). Stake advice uses fractional Kelly and is always
conservative (principle 0.1.5).
"""

from __future__ import annotations

from dataclasses import dataclass

DEFAULT_EV_THRESHOLD = 0.05
"""Minimum edge (5%) before a selection is flagged as value."""

DEFAULT_MIN_PROBABILITY = 0.10
"""Ignore long shots below this model probability; EV estimates there are noise."""

DEFAULT_KELLY_FRACTION = 0.25
"""Quarter Kelly: standard practice to dampen estimation error."""


def expected_value(model_probability: float, odds_decimal: float) -> float:
    """EV per 1 unit staked: p*odds - 1."""
    return model_probability * odds_decimal - 1.0


def kelly_fraction(
    model_probability: float,
    odds_decimal: float,
    fraction: float = DEFAULT_KELLY_FRACTION,
) -> float:
    """Fractional Kelly stake as a share of bankroll; never negative."""
    b = odds_decimal - 1.0
    if b <= 0:
        return 0.0
    q = 1.0 - model_probability
    full_kelly = (b * model_probability - q) / b
    return max(0.0, full_kelly * fraction)


@dataclass(slots=True)
class ValuePick:
    market_code: str
    selection_key: str
    model_probability: float
    odds_decimal: float
    implied_probability: float
    expected_value: float
    kelly_stake: float


def find_value_picks(
    model_markets: dict[str, dict[str, float]],
    offered_odds: dict[str, dict[str, float]],
    *,
    ev_threshold: float = DEFAULT_EV_THRESHOLD,
    min_probability: float = DEFAULT_MIN_PROBABILITY,
) -> list[ValuePick]:
    """Cross model probabilities with offered odds and keep +EV selections.

    ``model_markets`` and ``offered_odds`` are both keyed by iddaa market code
    then selection key. Only selections present in both are evaluated. Returns
    picks sorted by EV, highest first.
    """
    picks: list[ValuePick] = []
    for market_code, selections in model_markets.items():
        odds_for_market = offered_odds.get(market_code)
        if not odds_for_market:
            continue
        for selection_key, model_probability in selections.items():
            odds = odds_for_market.get(selection_key)
            if odds is None or odds <= 1.0:
                continue
            if model_probability < min_probability:
                continue
            ev = expected_value(model_probability, odds)
            if ev < ev_threshold:
                continue
            picks.append(
                ValuePick(
                    market_code=market_code,
                    selection_key=selection_key,
                    model_probability=model_probability,
                    odds_decimal=odds,
                    implied_probability=1.0 / odds,
                    expected_value=ev,
                    kelly_stake=kelly_fraction(model_probability, odds),
                )
            )
    picks.sort(key=lambda pick: pick.expected_value, reverse=True)
    return picks
