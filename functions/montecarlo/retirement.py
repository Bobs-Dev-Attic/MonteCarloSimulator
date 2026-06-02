"""Retirement accumulation + withdrawal Monte Carlo model.

Two phases are simulated year by year:

  1. Accumulation: each year the balance grows by a randomly sampled annual
     return and an annual contribution is added.
  2. Withdrawal (retirement): each year the balance grows by a randomly sampled
     return and an (inflation-adjusted) withdrawal is taken out.

The key output is the probability of *not* running out of money -- the fraction
of simulated paths whose balance is still positive at the end of the horizon.
"""

from __future__ import annotations

import numpy as np


def simulate_retirement(
    *,
    starting_balance: float,
    annual_contribution: float,
    years_to_retire: int,
    retirement_years: int,
    annual_withdrawal: float,
    mean_return: float,
    std_return: float,
    inflation: float = 0.0,
    n_sims: int = 10_000,
    seed: int | None = None,
) -> np.ndarray:
    """Simulate balance trajectories across accumulation + withdrawal.

    Args:
        starting_balance: Initial portfolio balance.
        annual_contribution: Amount added each accumulation year.
        years_to_retire: Number of accumulation years.
        retirement_years: Number of withdrawal years.
        annual_withdrawal: First-year withdrawal amount (grown by inflation).
        mean_return: Expected annual return (e.g. 0.06).
        std_return: Annual return volatility (e.g. 0.12).
        inflation: Annual inflation applied to withdrawals.
        n_sims: Number of simulated paths.
        seed: Optional RNG seed for reproducible runs.

    Returns:
        Array of shape ``(total_years + 1, n_sims)`` of yearly balances, floored
        at zero (a depleted path stays at zero).
    """
    if years_to_retire < 0 or retirement_years < 0:
        raise ValueError("year counts must be non-negative")
    if std_return < 0:
        raise ValueError("std_return must be non-negative")

    rng = np.random.default_rng(seed)
    total_years = years_to_retire + retirement_years

    history = np.empty((total_years + 1, n_sims), dtype=float)
    balance = np.full(n_sims, float(starting_balance))
    history[0] = balance

    for t in range(1, total_years + 1):
        r = rng.normal(mean_return, std_return, n_sims)
        balance = balance * (1.0 + r)
        if t <= years_to_retire:
            balance += annual_contribution
        else:
            withdrawal_year = t - years_to_retire - 1
            balance -= annual_withdrawal * ((1.0 + inflation) ** withdrawal_year)
        balance = np.maximum(balance, 0.0)
        history[t] = balance

    return history


def success_rate(history: np.ndarray) -> float:
    """Fraction of paths that finish with a positive balance."""
    return float(np.mean(history[-1] > 0.0))
