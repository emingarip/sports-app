from __future__ import annotations

import hashlib
import math
from collections.abc import Iterable


def safe_float(value: object) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return None
        try:
            return float(text)
        except ValueError:
            return None
    return None


def normalize_probabilities(values: Iterable[float | None]) -> list[float | None]:
    prepared = [value for value in values]
    total = sum(value for value in prepared if value is not None and value > 0)
    if total <= 0:
        return [None for _ in prepared]
    return [
        (value / total) if value is not None and value > 0 else None
        for value in prepared
    ]


def implied_probability(decimal_odds: float | None) -> float | None:
    if decimal_odds is None or decimal_odds <= 0:
        return None
    return 1.0 / decimal_odds


def normalize_implied_probabilities(decimal_odds: Iterable[float | None]) -> list[float | None]:
    implied = [implied_probability(value) for value in decimal_odds]
    return normalize_probabilities(implied)


def shin_probabilities(decimal_odds: Iterable[float | None]) -> list[float | None]:
    """De-vig quoted odds with Shin's (1993) method.

    Proportional normalisation spreads the bookmaker margin evenly across
    selections, which understates favourites and overstates longshots
    (favourite-longshot bias). Shin's insider-trading model loads more of the
    margin onto longshots; the insider fraction ``z`` is solved by bisection so
    the corrected probabilities sum to 1 (roadmap 2.5, ADR 9).

    Falls back to proportional normalisation when fewer than two odds are
    valid, the book has no overround, or the root search degenerates. Invalid
    entries stay ``None`` and keep their position.
    """
    implied = [implied_probability(value) for value in decimal_odds]
    valid = [(index, prob) for index, prob in enumerate(implied) if prob is not None and prob > 0]
    if len(valid) < 2:
        return normalize_probabilities(implied)
    booksum = sum(prob for _, prob in valid)
    if booksum <= 1.0:
        return normalize_probabilities(implied)

    def corrected(prob: float, z: float) -> float:
        return (math.sqrt(z * z + 4.0 * (1.0 - z) * (prob * prob) / booksum) - z) / (
            2.0 * (1.0 - z)
        )

    def corrected_sum(z: float) -> float:
        return sum(corrected(prob, z) for _, prob in valid)

    # corrected_sum(0) = sqrt(booksum) > 1 and decreases in z; find the bracket.
    lower, upper = 0.0, 0.1
    while corrected_sum(upper) > 1.0:
        upper = min(0.95, upper * 2.0)
        if upper >= 0.95 and corrected_sum(upper) > 1.0:
            return normalize_probabilities(implied)
    for _ in range(80):
        mid = (lower + upper) / 2.0
        if corrected_sum(mid) > 1.0:
            lower = mid
        else:
            upper = mid
    z_star = (lower + upper) / 2.0

    result: list[float | None] = [None for _ in implied]
    for index, prob in valid:
        result[index] = corrected(prob, z_star)
    return result


def standard_deviation(values: Iterable[float | None]) -> float | None:
    items = [value for value in values if value is not None]
    if len(items) < 2:
        return None
    mean = sum(items) / len(items)
    variance = sum((value - mean) ** 2 for value in items) / len(items)
    return math.sqrt(variance)


def sigmoid(value: float | None) -> float | None:
    if value is None:
        return None
    return 1.0 / (1.0 + math.exp(-value))


def zscore(value: float | None, *, mean: float | None, stddev: float | None) -> float | None:
    if value is None or mean is None or stddev in (None, 0):
        return None
    return (value - mean) / stddev


def mean(values: Iterable[float | None]) -> float | None:
    items = [value for value in values if value is not None]
    if not items:
        return None
    return sum(items) / len(items)


def weighted_mean(values: Iterable[tuple[float | None, float]]) -> float | None:
    numerator = 0.0
    denominator = 0.0
    for value, weight in values:
        if value is None or weight <= 0:
            continue
        numerator += value * weight
        denominator += weight
    if denominator <= 0:
        return None
    return numerator / denominator


def ewma_weight(days_ago: float, *, half_life_days: float) -> float:
    if half_life_days <= 0:
        return 1.0
    return 0.5 ** (days_ago / half_life_days)


def role_group(position: str | None) -> str | None:
    if not position:
        return None
    text = position.strip().upper()
    if text in {"GK", "G"}:
        return "GK"
    if text.startswith(("D", "CB", "LB", "RB", "WB")):
        return "DEF"
    if text.startswith(("M", "DM", "CM", "AM", "LM", "RM")):
        return "MID"
    if text.startswith(("F", "S", "W", "ST", "CF", "LW", "RW")):
        return "ATT"
    return None


def parse_formation(formation: str | None) -> dict[str, int] | None:
    if not formation:
        return None
    parts = [part.strip() for part in formation.split("-") if part.strip().isdigit()]
    if not parts:
        return None
    numbers = [int(part) for part in parts]
    if not numbers:
        return None
    defenders = numbers[0] if numbers else 4
    attackers = numbers[-1] if len(numbers) > 1 else 2
    midfielders = max(sum(numbers[1:-1]), 0) if len(numbers) > 2 else max(10 - defenders - attackers, 0)
    return {"GK": 1, "DEF": defenders, "MID": midfielders, "ATT": attackers}


def lineup_strength(
    *,
    gk: float | None,
    defenders: Iterable[float | None],
    midfielders: Iterable[float | None],
    attackers: Iterable[float | None],
) -> float | None:
    defender_mean = mean(defenders)
    midfielder_mean = mean(midfielders)
    attacker_mean = mean(attackers)
    if gk is None and defender_mean is None and midfielder_mean is None and attacker_mean is None:
        return None
    return (
        (gk or 0.0) * 0.12
        + (defender_mean or 0.0) * 0.33
        + (midfielder_mean or 0.0) * 0.30
        + (attacker_mean or 0.0) * 0.25
    )


def jaccard_similarity(left: set[str], right: set[str]) -> float | None:
    if not left and not right:
        return None
    union = left | right
    if not union:
        return None
    return len(left & right) / len(union)


def stable_bucket(values: Iterable[object], *, buckets: int) -> int | None:
    if buckets <= 0:
        return None
    text = "|".join("" if value is None else str(value) for value in values)
    if not text:
        return None
    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
    return int(digest[:12], 16) % buckets


def renormalized_weighted_sum(values: Iterable[tuple[float | None, float]]) -> float | None:
    prepared = [(value, weight) for value, weight in values if value is not None and weight > 0]
    if not prepared:
        return None
    weight_sum = sum(weight for _, weight in prepared)
    return sum(value * (weight / weight_sum) for value, weight in prepared)


def score_state_class(score_diff: int | None) -> str | None:
    if score_diff is None:
        return None
    if score_diff >= 2:
        return "home_leading_by_2p"
    if score_diff == 1:
        return "home_leading_by_1"
    if score_diff == 0:
        return "draw"
    if score_diff == -1:
        return "away_leading_by_1"
    return "away_leading_by_2p"


def market_state_class(
    *,
    market_volatility_last5: float | None,
    live_home_prob: float | None,
    live_draw_prob: float | None,
    live_away_prob: float | None,
) -> str | None:
    if market_volatility_last5 is not None and market_volatility_last5 >= 0.08:
        return "chaotic_market"
    if live_home_prob is not None and live_home_prob >= 0.60:
        return "strong_home_live"
    if live_away_prob is not None and live_away_prob >= 0.60:
        return "strong_away_live"
    if live_draw_prob is not None and live_draw_prob >= 0.40:
        return "draw_heavy_live"
    if live_home_prob is None and live_draw_prob is None and live_away_prob is None:
        return None
    return "balanced_live"
