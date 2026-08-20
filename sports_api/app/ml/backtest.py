"""Betting-simulation backtest core.

"Model is calibrated" and "model makes money" are different claims (roadmap
2.5): calibration metrics live in ``calibration.py``, this module answers the
second question by replaying settled picks as a bankroll simulation — real
odds (margin included), fractional Kelly or flat staking, ROI and maximum
drawdown. Walk-forward data assembly happens at the service layer; these are
pure functions over already-settled bets.
"""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from dataclasses import dataclass

from app.ml.value_detection import DEFAULT_KELLY_FRACTION, kelly_fraction


@dataclass(slots=True)
class SettledBet:
    """One settled pick: the probability used to stake, the odds taken, the outcome."""

    probability: float
    odds_decimal: float
    won: bool


@dataclass(slots=True)
class BacktestReport:
    n_bets: int
    n_skipped: int
    total_staked: float
    profit: float
    roi: float
    hit_rate: float
    max_drawdown: float
    starting_bankroll: float
    final_bankroll: float


def simulate_bets(
    bets: Iterable[SettledBet],
    *,
    starting_bankroll: float = 100.0,
    kelly_frac: float = DEFAULT_KELLY_FRACTION,
    flat_stake: float | None = None,
) -> BacktestReport:
    """Replay settled bets sequentially against a bankroll.

    Stakes are fractional Kelly on the running bankroll by default; pass
    ``flat_stake`` to stake a fixed amount instead. Bets with no positive
    Kelly stake (no modelled edge) are skipped, mirroring live behaviour.
    ``max_drawdown`` is the largest peak-to-trough bankroll drop as a share
    of the peak.
    """
    if starting_bankroll <= 0:
        raise ValueError("starting_bankroll must be positive")
    if flat_stake is not None and flat_stake <= 0:
        raise ValueError("flat_stake must be positive when provided")

    bankroll = starting_bankroll
    peak = starting_bankroll
    max_drawdown = 0.0
    n_bets = 0
    n_skipped = 0
    n_won = 0
    total_staked = 0.0

    for bet in bets:
        if flat_stake is not None:
            stake = min(flat_stake, bankroll)
        else:
            share = kelly_fraction(bet.probability, bet.odds_decimal, fraction=kelly_frac)
            stake = bankroll * share
        if stake <= 0 or bankroll <= 0:
            n_skipped += 1
            continue
        n_bets += 1
        total_staked += stake
        if bet.won:
            n_won += 1
            bankroll += stake * (bet.odds_decimal - 1.0)
        else:
            bankroll -= stake
        peak = max(peak, bankroll)
        if peak > 0:
            max_drawdown = max(max_drawdown, (peak - bankroll) / peak)

    profit = bankroll - starting_bankroll
    return BacktestReport(
        n_bets=n_bets,
        n_skipped=n_skipped,
        total_staked=round(total_staked, 6),
        profit=round(profit, 6),
        roi=round(profit / total_staked, 6) if total_staked > 0 else 0.0,
        hit_rate=round(n_won / n_bets, 6) if n_bets else 0.0,
        max_drawdown=round(max_drawdown, 6),
        starting_bankroll=starting_bankroll,
        final_bankroll=round(bankroll, 6),
    )


def compare_stakings(
    bets: Sequence[SettledBet],
    *,
    starting_bankroll: float = 100.0,
    kelly_frac: float = DEFAULT_KELLY_FRACTION,
    flat_stake: float = 1.0,
) -> dict[str, BacktestReport]:
    """Run the same settled bets under Kelly and flat staking side by side."""
    return {
        "kelly": simulate_bets(
            bets, starting_bankroll=starting_bankroll, kelly_frac=kelly_frac
        ),
        "flat": simulate_bets(
            bets, starting_bankroll=starting_bankroll, flat_stake=flat_stake
        ),
    }
