"""Estimate GBM simulation inputs from historical prices.

The portfolio (GBM) model needs two numbers: an annual drift ``mu`` and an
annual volatility ``sigma``. Until now both were typed in by hand. This module
derives them from a matrix of historical closing prices so an advisor can build
a *real* portfolio of tickers and let the data set the assumptions.

Everything here is pure NumPy (no pandas, no network) so it is fast and trivial
to unit-test. The market-data fetch that produces the price matrix lives in the
sibling :mod:`montecarlo.marketdata` module, keeping the (flaky, unsanctioned)
network dependency isolated from this deterministic math.

Conventions
-----------
* Prices are a 2-D array shaped ``(T, A)`` — ``T`` chronological observations of
  ``A`` assets (a single asset is shape ``(T, 1)``).
* We work in **log returns** because GBM is log-normal:
  ``r_t = ln(P_t / P_{t-1})``.
* ``mu`` matches the drift convention of :func:`montecarlo.gbm.simulate_gbm`,
  where ``E[S_T] = S_0 * exp(mu * T)``. Since the mean per-step *log* return is
  ``(mu - 0.5 * sigma**2) * dt``, we recover ``mu`` from the sample mean log
  return ``m`` and annual variance ``s2`` as ``mu = m_annual + 0.5 * s2``.
"""

from __future__ import annotations

import numpy as np

TRADING_DAYS = 252


def log_returns(prices: np.ndarray) -> np.ndarray:
    """Period-over-period log returns of a ``(T, A)`` price matrix.

    Returns an array shaped ``(T - 1, A)``. Raises if there are fewer than two
    observations or any price is non-positive (log is undefined there).
    """
    p = np.asarray(prices, dtype=float)
    if p.ndim == 1:
        p = p[:, None]
    if p.ndim != 2:
        raise ValueError("prices must be 1-D or 2-D")
    if p.shape[0] < 2:
        raise ValueError("need at least two price observations to compute returns")
    if not np.all(np.isfinite(p)) or np.any(p <= 0):
        raise ValueError("prices must be finite and strictly positive")
    return np.diff(np.log(p), axis=0)


def annualized_asset_stats(
    prices: np.ndarray, trading_days: int = TRADING_DAYS
) -> list[dict]:
    """Per-asset annualized GBM inputs.

    For each column returns ``{"mu": float, "sigma": float,
    "mean_log_return": float}`` where ``sigma`` is the annualized standard
    deviation of log returns and ``mu`` is the GBM drift (see module docstring).
    """
    r = log_returns(prices)
    mean_daily = r.mean(axis=0)
    # ddof=1 (sample std) — we are estimating from a finite sample.
    var_daily = r.var(axis=0, ddof=1)
    sigma = np.sqrt(var_daily * trading_days)
    mean_annual = mean_daily * trading_days
    mu = mean_annual + 0.5 * sigma**2
    return [
        {
            "mu": float(mu[i]),
            "sigma": float(sigma[i]),
            "mean_log_return": float(mean_annual[i]),
        }
        for i in range(r.shape[1])
    ]


def correlation_matrix(prices: np.ndarray) -> list[list[float]]:
    """Correlation matrix of the assets' log returns as nested lists.

    A single-asset portfolio yields ``[[1.0]]``.
    """
    r = log_returns(prices)
    if r.shape[1] == 1:
        return [[1.0]]
    # rowvar=False: each column is a variable (asset), each row an observation.
    corr = np.corrcoef(r, rowvar=False)
    return np.atleast_2d(corr).tolist()


def _normalize_weights(weights, n_assets: int) -> np.ndarray:
    if weights is None:
        # Equal weight when unspecified.
        return np.full(n_assets, 1.0 / n_assets)
    w = np.asarray(weights, dtype=float)
    if w.shape != (n_assets,):
        raise ValueError(
            f"weights length {w.shape} does not match {n_assets} assets"
        )
    if np.any(w < 0):
        raise ValueError("weights must be non-negative (no short positions)")
    total = w.sum()
    if total <= 0:
        raise ValueError("weights must sum to a positive number")
    return w / total


def portfolio_gbm_inputs(
    prices: np.ndarray,
    weights=None,
    trading_days: int = TRADING_DAYS,
) -> dict:
    """Collapse a multi-asset portfolio into a single ``(mu, sigma)`` pair.

    The single-asset GBM simulator needs one drift and one volatility, so the
    basket is treated as a synthetic asset whose per-step log return is the
    weighted sum of the constituents' log returns (exact under continuous
    rebalancing; a first-order approximation otherwise). Diversification is
    captured through the full covariance matrix:

        sigma_p = sqrt(wᵀ Σ w)      with Σ = annualized covariance of log returns
        mu_p    = (w · m)·days + 0.5·sigma_p²

    Args:
        prices: ``(T, A)`` price matrix.
        weights: Per-asset weights; ``None`` means equal-weight. Normalized to
            sum to 1.
        trading_days: Periods per year for annualization (252 for daily data).

    Returns:
        ``{"mu", "sigma", "weights", "assets": [per-asset stats...],
        "correlation": [[...]], "observations": int}``.
    """
    r = log_returns(prices)
    n_obs, n_assets = r.shape
    w = _normalize_weights(weights, n_assets)

    mean_daily = r.mean(axis=0)
    # Annualized covariance of daily log returns (sample covariance, ddof=1).
    cov_daily = np.atleast_2d(np.cov(r, rowvar=False, ddof=1))
    cov_annual = cov_daily * trading_days

    var_p = float(w @ cov_annual @ w)
    sigma_p = float(np.sqrt(max(var_p, 0.0)))
    mean_annual_p = float((w @ mean_daily) * trading_days)
    mu_p = mean_annual_p + 0.5 * var_p

    return {
        "mu": mu_p,
        "sigma": sigma_p,
        "weights": w.tolist(),
        "assets": annualized_asset_stats(prices, trading_days),
        "correlation": correlation_matrix(prices),
        "observations": int(n_obs),
    }
