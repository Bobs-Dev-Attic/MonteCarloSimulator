"""Unit tests for the Monte Carlo math (no Firebase dependency required)."""

import numpy as np
import pytest

from montecarlo import aggregate
from montecarlo.gbm import simulate_gbm
from montecarlo.retirement import simulate_retirement, success_rate


# --------------------------- GBM ---------------------------------------------

def test_gbm_shape_and_initial_value():
    paths = simulate_gbm(
        beginning_value=1000, mu=0.07, sigma=0.15, years=2,
        steps_per_year=252, n_sims=500, seed=1,
    )
    assert paths.shape == (2 * 252 + 1, 500)
    assert np.allclose(paths[0], 1000)


def test_gbm_is_reproducible_with_seed():
    kw = dict(beginning_value=1000, mu=0.05, sigma=0.2, years=1, n_sims=300, seed=42)
    assert np.array_equal(simulate_gbm(**kw), simulate_gbm(**kw))


def test_gbm_mean_matches_analytic_expectation():
    # E[S_T] = S0 * exp(mu * T). Check within Monte Carlo tolerance.
    s0, mu, years = 1000.0, 0.08, 5.0
    paths = simulate_gbm(
        beginning_value=s0, mu=mu, sigma=0.18, years=years,
        steps_per_year=252, n_sims=40_000, seed=7,
    )
    analytic = s0 * np.exp(mu * years)
    assert abs(np.mean(paths[-1]) - analytic) / analytic < 0.03


def test_gbm_zero_volatility_is_deterministic():
    paths = simulate_gbm(
        beginning_value=1000, mu=0.10, sigma=0.0, years=3,
        steps_per_year=12, n_sims=10, seed=0,
    )
    expected = 1000 * np.exp(0.10 * 3)  # drift only, no diffusion
    assert np.allclose(paths[-1], expected)


def test_gbm_contributions_increase_terminal_value():
    base = simulate_gbm(beginning_value=1000, mu=0.05, sigma=0.1, years=2,
                        steps_per_year=12, n_sims=2000, seed=3)
    with_contrib = simulate_gbm(beginning_value=1000, mu=0.05, sigma=0.1, years=2,
                                steps_per_year=12, n_sims=2000, seed=3,
                                contribution_per_step=50)
    assert np.mean(with_contrib[-1]) > np.mean(base[-1])


def test_gbm_rejects_bad_inputs():
    with pytest.raises(ValueError):
        simulate_gbm(beginning_value=-1, mu=0.05, sigma=0.1, years=1)
    with pytest.raises(ValueError):
        simulate_gbm(beginning_value=100, mu=0.05, sigma=-0.1, years=1)


# ----------------------- Retirement ------------------------------------------

def test_retirement_shape():
    hist = simulate_retirement(
        starting_balance=100_000, annual_contribution=10_000,
        years_to_retire=20, retirement_years=30, annual_withdrawal=40_000,
        mean_return=0.06, std_return=0.12, n_sims=500, seed=1,
    )
    assert hist.shape == (50 + 1, 500)


def test_retirement_success_rate_in_unit_interval():
    hist = simulate_retirement(
        starting_balance=500_000, annual_contribution=0,
        years_to_retire=0, retirement_years=30, annual_withdrawal=25_000,
        mean_return=0.05, std_return=0.1, n_sims=2000, seed=2,
    )
    sr = success_rate(hist)
    assert 0.0 <= sr <= 1.0


def test_retirement_balance_never_negative():
    hist = simulate_retirement(
        starting_balance=10_000, annual_contribution=0,
        years_to_retire=0, retirement_years=40, annual_withdrawal=50_000,
        mean_return=0.04, std_return=0.15, n_sims=500, seed=5,
    )
    assert np.all(hist >= 0.0)


def test_retirement_higher_withdrawal_lowers_success():
    common = dict(starting_balance=500_000, annual_contribution=0,
                  years_to_retire=0, retirement_years=30,
                  mean_return=0.05, std_return=0.1, n_sims=3000, seed=9)
    low = success_rate(simulate_retirement(annual_withdrawal=20_000, **common))
    high = success_rate(simulate_retirement(annual_withdrawal=60_000, **common))
    assert low > high


# ----------------------- Aggregation -----------------------------------------

def test_percentile_bands_are_ordered_and_downsampled():
    paths = simulate_gbm(beginning_value=1000, mu=0.07, sigma=0.2, years=3,
                        steps_per_year=252, n_sims=2000, seed=11)
    bands = aggregate.percentile_bands(paths, max_points=80)
    assert len(bands["steps"]) <= 80
    p5 = np.array(bands["p5"]); p50 = np.array(bands["p50"]); p95 = np.array(bands["p95"])
    assert np.all(p5 <= p50) and np.all(p50 <= p95)


def test_histogram_counts_sum_to_sample_size():
    tv = np.random.default_rng(0).normal(100, 10, 5000)
    hist = aggregate.terminal_histogram(tv, bins=40)
    assert sum(hist["counts"]) == 5000
    assert len(hist["edges"]) == 41


def test_summary_stats_fields_and_ranges():
    tv = np.array([80.0, 90, 100, 110, 120, 130])
    s = aggregate.summary_stats(tv, beginning_value=100.0)
    assert s["min"] == 80.0 and s["max"] == 130.0
    assert 0.0 <= s["prob_loss"] <= 1.0
    assert s["var_95"] >= 0.0
