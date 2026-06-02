"""Geometric Brownian Motion (GBM) path simulation.

Models the price/value of a portfolio or asset as:

    S_{t+1} = S_t * exp((mu - 0.5 * sigma**2) * dt + sigma * sqrt(dt) * Z)

where Z ~ N(0, 1). This is the standard log-normal model: the deterministic
baseline (EndingValue = BeginningValue * (1 + Return)) is replaced by a Return
that is a random variable defined by an expected mean (drift, mu) and
volatility (standard deviation, sigma).
"""

from __future__ import annotations

import numpy as np


def simulate_gbm(
    *,
    beginning_value: float,
    mu: float,
    sigma: float,
    years: float,
    steps_per_year: int = 252,
    n_sims: int = 10_000,
    contribution_per_step: float = 0.0,
    seed: int | None = None,
) -> np.ndarray:
    """Generate ``n_sims`` GBM paths.

    Args:
        beginning_value: Starting value S0 (must be > 0).
        mu: Expected annual return (drift), e.g. 0.07 for 7%.
        sigma: Annual volatility (standard deviation), e.g. 0.15.
        years: Time horizon in years.
        steps_per_year: Discretization granularity (252 = trading days).
        n_sims: Number of simulated paths.
        contribution_per_step: Optional cash added each step (e.g. recurring
            deposits). When zero, a fast closed-form cumulative product is used.
        seed: Optional RNG seed for reproducible runs.

    Returns:
        Array of shape ``(n_steps + 1, n_sims)`` where row 0 is the (constant)
        beginning value and the final row is the terminal value of each path.
    """
    if beginning_value <= 0:
        raise ValueError("beginning_value must be positive")
    if sigma < 0:
        raise ValueError("sigma must be non-negative")
    if years <= 0:
        raise ValueError("years must be positive")

    rng = np.random.default_rng(seed)
    n_steps = max(1, int(round(years * steps_per_year)))
    dt = 1.0 / steps_per_year

    drift = (mu - 0.5 * sigma**2) * dt
    z = rng.standard_normal((n_steps, n_sims))
    log_step = drift + sigma * np.sqrt(dt) * z  # per-step log growth factors

    paths = np.empty((n_steps + 1, n_sims), dtype=float)
    paths[0] = beginning_value

    if contribution_per_step == 0.0:
        # Fast path: terminal-from-start is a cumulative product of growth.
        growth = np.exp(np.cumsum(log_step, axis=0))
        paths[1:] = beginning_value * growth
    else:
        # Contributions break the closed form; step iteratively (still
        # vectorized across all n_sims simultaneously).
        step_factor = np.exp(log_step)
        balance = np.full(n_sims, float(beginning_value))
        for t in range(n_steps):
            balance = balance * step_factor[t] + contribution_per_step
            paths[t + 1] = balance

    return paths
