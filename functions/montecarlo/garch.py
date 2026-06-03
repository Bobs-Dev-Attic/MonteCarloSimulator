"""GBM with GARCH(1,1) conditional variance.

Replaces the constant per-step variance ``sigma**2 * dt`` of vanilla GBM with
a time-varying ``h_t`` that follows the GARCH(1,1) recursion

    h_{t+1} = omega + alpha * eps_t**2 + beta * h_t

where ``eps_t = sqrt(h_t) * z_t`` is the per-step demeaned shock. omega is
calibrated so the long-run variance ``omega / (1 - alpha - beta)`` equals the
per-step variance ``sigma**2 / steps_per_year``; ``h_0`` starts at that long-run
value so the very first step matches a constant-sigma GBM step in expectation.

This is intentionally a per-step Python loop over time (vectorized across
``n_sims``) because GARCH has a sequential dependence on the previous step's
variance.
"""

from __future__ import annotations

import numpy as np


def simulate_gbm_garch(
    *,
    beginning_value: float,
    mu: float,
    sigma: float,
    years: float,
    steps_per_year: int = 252,
    n_sims: int = 10_000,
    contribution_per_step: float = 0.0,
    seed: int | None = None,
    alpha: float = 0.10,
    beta: float = 0.85,
) -> np.ndarray:
    """Generate ``n_sims`` GBM-GARCH paths.

    Shape and units match :func:`montecarlo.gbm.simulate_gbm` so the same
    aggregation pipeline works on both. ``sigma`` is the *annual long-run*
    volatility target — instantaneous volatility fluctuates around it.

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
        alpha: GARCH(1,1) ARCH coefficient (weight on lagged squared shock).
        beta: GARCH(1,1) GARCH coefficient (weight on lagged conditional variance).

    Returns:
        Array of shape ``(n_steps + 1, n_sims)`` with row 0 equal to
        ``beginning_value``.
    """
    if beginning_value <= 0:
        raise ValueError("beginning_value must be positive")
    if sigma < 0:
        raise ValueError("sigma must be non-negative")
    if years <= 0:
        raise ValueError("years must be positive")
    if not (0 <= alpha < 1 and 0 <= beta < 1 and alpha + beta < 1):
        raise ValueError("require 0 <= alpha, beta < 1 and alpha + beta < 1")

    rng = np.random.default_rng(seed)
    n_steps = max(1, int(round(years * steps_per_year)))
    dt = 1.0 / steps_per_year

    long_run_var_step = (sigma ** 2) * dt
    omega = long_run_var_step * (1.0 - alpha - beta)

    h = np.full(n_sims, long_run_var_step, dtype=float)
    log_step = np.empty((n_steps, n_sims), dtype=float)

    for t in range(n_steps):
        z = rng.standard_normal(n_sims)
        sigma_step = np.sqrt(h)
        eps = sigma_step * z
        # Per-step drift uses the *current* conditional variance for the Ito
        # correction so the expected log step is mu*dt regardless of clustering.
        drift = mu * dt - 0.5 * h
        log_step[t] = drift + eps
        h = omega + alpha * eps ** 2 + beta * h

    paths = np.empty((n_steps + 1, n_sims), dtype=float)
    paths[0] = beginning_value

    if contribution_per_step == 0.0:
        growth = np.exp(np.cumsum(log_step, axis=0))
        paths[1:] = beginning_value * growth
    else:
        step_factor = np.exp(log_step)
        balance = np.full(n_sims, float(beginning_value))
        for t in range(n_steps):
            balance = balance * step_factor[t] + contribution_per_step
            paths[t + 1] = balance

    return paths
