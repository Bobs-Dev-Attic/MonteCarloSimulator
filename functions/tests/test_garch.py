"""Tests for GBM with GARCH(1,1) conditional variance."""

from __future__ import annotations

import numpy as np
import pytest

from montecarlo.gbm import simulate_gbm
from montecarlo.garch import simulate_gbm_garch


def _common_kwargs():
    return dict(
        beginning_value=10_000.0,
        mu=0.07,
        sigma=0.15,
        years=10.0,
        steps_per_year=252,
        n_sims=500,
    )


def test_shape_matches_gbm():
    paths = simulate_gbm_garch(**_common_kwargs(), seed=1)
    expected_steps = int(round(10.0 * 252)) + 1
    assert paths.shape == (expected_steps, 500)


def test_reproducible_with_seed():
    a = simulate_gbm_garch(**_common_kwargs(), seed=42)
    b = simulate_gbm_garch(**_common_kwargs(), seed=42)
    np.testing.assert_array_equal(a, b)


def test_different_seed_gives_different_paths():
    a = simulate_gbm_garch(**_common_kwargs(), seed=1)
    b = simulate_gbm_garch(**_common_kwargs(), seed=2)
    assert not np.allclose(a, b)


def test_long_run_variance_matches_sigma_target():
    """Empirical per-step log-return variance should converge to
    (sigma**2 / steps_per_year) given enough steps and paths."""
    sigma = 0.20
    steps_per_year = 252
    years = 50  # long horizon for convergence
    paths = simulate_gbm_garch(
        beginning_value=10_000.0,
        mu=0.0,  # zero drift makes empirical variance cleanest
        sigma=sigma,
        years=years,
        steps_per_year=steps_per_year,
        n_sims=2_000,
        seed=7,
    )
    log_returns = np.diff(np.log(paths), axis=0)
    empirical_var_step = float(np.var(log_returns))
    target_var_step = (sigma ** 2) / steps_per_year
    # Tolerance: within 8% of target (GARCH adds sampling noise on top of GBM)
    assert empirical_var_step == pytest.approx(target_var_step, rel=0.08)


def test_terminal_tail_wider_than_gbm_on_average():
    """With the same sigma, GARCH should produce at least as wide a terminal
    P5-P95 spread as GBM in the typical case, averaged across seeds.

    Uses an ensemble of seeds because a single seed's draw can go either way.
    """
    kwargs = dict(
        beginning_value=10_000.0,
        mu=0.05,
        sigma=0.20,
        years=10.0,
        steps_per_year=252,
        n_sims=3_000,
    )
    spreads = []
    for seed in range(8):
        gbm = simulate_gbm(**kwargs, seed=seed)
        garch = simulate_gbm_garch(**kwargs, seed=seed)
        gbm_spread = float(np.percentile(gbm[-1], 95) - np.percentile(gbm[-1], 5))
        garch_spread = float(np.percentile(garch[-1], 95) - np.percentile(garch[-1], 5))
        spreads.append(garch_spread - gbm_spread)
    # On average, GARCH spread should be >= GBM spread (volatility clustering
    # fattens tails). Allow a tiny negative tolerance to absorb sampling noise.
    assert float(np.mean(spreads)) > -100.0
