"""Tests for deriving GBM inputs from historical prices.

All network-free: prices are constructed synthetically (a known GBM process or
hand-built series) so the estimators have a ground truth to converge to.
"""

from __future__ import annotations

import numpy as np
import pytest

from montecarlo import estimate
from montecarlo.gbm import simulate_gbm


def _single_gbm_price_series(mu, sigma, *, days=252 * 30, seed=0):
    """One long daily GBM price path shaped (T, 1) with known mu/sigma."""
    path = simulate_gbm(
        beginning_value=100.0,
        mu=mu,
        sigma=sigma,
        years=days / estimate.TRADING_DAYS,
        steps_per_year=estimate.TRADING_DAYS,
        n_sims=1,
        seed=seed,
    )
    return path  # shape (days + 1, 1)


# --------------------------- log returns -------------------------------------

def test_log_returns_shape_and_values():
    prices = np.array([[100.0], [110.0], [121.0]])
    r = estimate.log_returns(prices)
    assert r.shape == (2, 1)
    assert np.allclose(r[:, 0], np.log(1.1))


def test_log_returns_accepts_1d():
    r = estimate.log_returns(np.array([100.0, 105.0]))
    assert r.shape == (1, 1)


def test_log_returns_rejects_bad_prices():
    with pytest.raises(ValueError):
        estimate.log_returns(np.array([[100.0]]))  # only one observation
    with pytest.raises(ValueError):
        estimate.log_returns(np.array([[100.0], [-1.0]]))  # non-positive


# --------------------------- annualization -----------------------------------

def test_recovers_known_mu_sigma_from_gbm_series():
    true_mu, true_sigma = 0.09, 0.18
    prices = _single_gbm_price_series(true_mu, true_sigma, days=252 * 60, seed=3)
    stats = estimate.annualized_asset_stats(prices)[0]
    # Long sample => estimates converge to the generating parameters.
    assert stats["sigma"] == pytest.approx(true_sigma, rel=0.05)
    assert stats["mu"] == pytest.approx(true_mu, abs=0.03)


def test_zero_drift_flat_volatility_series():
    # Balanced up/down ladder: the log returns net to exactly zero (mean drift
    # ~ 0) while volatility is clearly positive.
    prices = np.array([[100.0], [110.0], [100.0], [110.0], [100.0]])
    stats = estimate.annualized_asset_stats(prices)[0]
    assert stats["sigma"] > 0
    assert stats["mean_log_return"] == pytest.approx(0.0, abs=1e-9)


# --------------------------- correlation -------------------------------------

def test_single_asset_correlation_is_identity():
    prices = _single_gbm_price_series(0.05, 0.2, days=500, seed=1)
    assert estimate.correlation_matrix(prices) == [[1.0]]


def test_two_asset_correlation_is_symmetric_unit_diagonal():
    rng = np.random.default_rng(0)
    base = np.cumprod(1 + rng.normal(0.0003, 0.01, (400, 1)), axis=0) * 100
    other = np.cumprod(1 + rng.normal(0.0005, 0.012, (400, 1)), axis=0) * 50
    prices = np.hstack([base, other])
    corr = estimate.correlation_matrix(prices)
    assert len(corr) == 2 and len(corr[0]) == 2
    assert corr[0][0] == pytest.approx(1.0) and corr[1][1] == pytest.approx(1.0)
    assert corr[0][1] == pytest.approx(corr[1][0])


# --------------------------- portfolio collapse ------------------------------

def test_portfolio_single_asset_matches_asset_stats():
    prices = _single_gbm_price_series(0.07, 0.2, days=252 * 20, seed=2)
    port = estimate.portfolio_gbm_inputs(prices)
    asset = estimate.annualized_asset_stats(prices)[0]
    assert port["mu"] == pytest.approx(asset["mu"], rel=1e-6)
    assert port["sigma"] == pytest.approx(asset["sigma"], rel=1e-6)
    assert port["weights"] == [1.0]
    assert port["observations"] == prices.shape[0] - 1


def test_portfolio_default_weights_are_equal():
    rng = np.random.default_rng(5)
    prices = np.cumprod(1 + rng.normal(0.0004, 0.01, (300, 3)), axis=0) * 100
    port = estimate.portfolio_gbm_inputs(prices)
    assert port["weights"] == pytest.approx([1 / 3, 1 / 3, 1 / 3])
    assert len(port["assets"]) == 3
    assert len(port["correlation"]) == 3


def test_portfolio_weights_are_normalized():
    rng = np.random.default_rng(6)
    prices = np.cumprod(1 + rng.normal(0.0004, 0.01, (300, 2)), axis=0) * 100
    port = estimate.portfolio_gbm_inputs(prices, weights=[3, 1])
    assert port["weights"] == pytest.approx([0.75, 0.25])


def test_diversification_lowers_portfolio_volatility():
    """Two imperfectly correlated assets => portfolio sigma below the weighted
    average of the individual sigmas (the diversification benefit)."""
    rng = np.random.default_rng(11)
    a = rng.normal(0.0003, 0.012, 800)
    b = rng.normal(0.0003, 0.012, 800)  # independent draws => low correlation
    prices = np.column_stack([
        np.cumprod(1 + a) * 100,
        np.cumprod(1 + b) * 100,
    ])
    port = estimate.portfolio_gbm_inputs(prices, weights=[0.5, 0.5])
    sigmas = [s["sigma"] for s in port["assets"]]
    weighted_avg_sigma = 0.5 * sigmas[0] + 0.5 * sigmas[1]
    assert port["sigma"] < weighted_avg_sigma


def test_portfolio_rejects_mismatched_weights():
    rng = np.random.default_rng(7)
    prices = np.cumprod(1 + rng.normal(0.0004, 0.01, (50, 2)), axis=0) * 100
    with pytest.raises(ValueError):
        estimate.portfolio_gbm_inputs(prices, weights=[1.0])
    with pytest.raises(ValueError):
        estimate.portfolio_gbm_inputs(prices, weights=[-0.5, 1.5])
