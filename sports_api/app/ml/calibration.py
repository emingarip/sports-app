"""Calibration metrics: the platform's honesty layer.

The product promise is not "we predict winners" but "our probabilities mean
what they say". These metrics quantify that promise and are exposed through
the API (roadmap principle 0.1.1).
"""

from __future__ import annotations

import math
from dataclasses import dataclass


def brier_score(probabilities: list[float], outcomes: list[int]) -> float:
    """Mean squared error between predicted probability and binary outcome."""
    if len(probabilities) != len(outcomes) or not probabilities:
        raise ValueError("probabilities and outcomes must be equal-length, non-empty lists.")
    return sum(
        (probability - outcome) ** 2
        for probability, outcome in zip(probabilities, outcomes, strict=True)
    ) / len(probabilities)


def log_loss(probabilities: list[float], outcomes: list[int], eps: float = 1e-12) -> float:
    if len(probabilities) != len(outcomes) or not probabilities:
        raise ValueError("probabilities and outcomes must be equal-length, non-empty lists.")
    total = 0.0
    for probability, outcome in zip(probabilities, outcomes, strict=True):
        clipped = min(1.0 - eps, max(eps, probability))
        total += -math.log(clipped) if outcome else -math.log(1.0 - clipped)
    return total / len(probabilities)


def multiclass_brier(
    probability_rows: list[dict[str, float]],
    outcomes: list[str],
) -> float:
    """Multi-class Brier score (e.g. 1X2): sum of squared errors per class."""
    if len(probability_rows) != len(outcomes) or not probability_rows:
        raise ValueError("probability_rows and outcomes must be equal-length, non-empty lists.")
    total = 0.0
    for probabilities, outcome in zip(probability_rows, outcomes, strict=True):
        for key, probability in probabilities.items():
            actual = 1.0 if key == outcome else 0.0
            total += (probability - actual) ** 2
    return total / len(probability_rows)


@dataclass(slots=True)
class ReliabilityBin:
    lower: float
    upper: float
    count: int
    mean_predicted: float
    observed_rate: float


def reliability_bins(
    probabilities: list[float],
    outcomes: list[int],
    n_bins: int = 10,
) -> list[ReliabilityBin]:
    """Group predictions into probability bins and compare with observed rates."""
    if len(probabilities) != len(outcomes):
        raise ValueError("probabilities and outcomes must have equal length.")
    buckets: list[list[tuple[float, int]]] = [[] for _ in range(n_bins)]
    for probability, outcome in zip(probabilities, outcomes, strict=True):
        index = min(n_bins - 1, max(0, int(probability * n_bins)))
        buckets[index].append((probability, outcome))

    bins: list[ReliabilityBin] = []
    for index, bucket in enumerate(buckets):
        lower = index / n_bins
        upper = (index + 1) / n_bins
        if not bucket:
            bins.append(
                ReliabilityBin(
                    lower=lower, upper=upper, count=0, mean_predicted=0.0, observed_rate=0.0
                )
            )
            continue
        mean_predicted = sum(item[0] for item in bucket) / len(bucket)
        observed_rate = sum(item[1] for item in bucket) / len(bucket)
        bins.append(
            ReliabilityBin(
                lower=lower,
                upper=upper,
                count=len(bucket),
                mean_predicted=mean_predicted,
                observed_rate=observed_rate,
            )
        )
    return bins


def expected_calibration_error(
    probabilities: list[float],
    outcomes: list[int],
    n_bins: int = 10,
) -> float:
    """Weighted mean |predicted - observed| across reliability bins."""
    bins = reliability_bins(probabilities, outcomes, n_bins)
    total = sum(bin_.count for bin_ in bins)
    if total == 0:
        return 0.0
    return sum(
        bin_.count * abs(bin_.mean_predicted - bin_.observed_rate) for bin_ in bins
    ) / total
