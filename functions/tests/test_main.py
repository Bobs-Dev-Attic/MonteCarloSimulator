"""Tests for the request-shape behavior of main._run_gbm.

Exercises the pure-Python runner directly rather than the wrapped
firebase_functions callable.
"""

from __future__ import annotations

import numpy as np
import pytest

import main
from montecarlo import marketdata


_BASE_INPUTS = {
    "beginning_value": 10_000.0,
    "mu": 0.07,
    "sigma": 0.15,
    "years": 5.0,
    "steps_per_year": 252,
}


def test_run_gbm_no_comparison_by_default():
    result = main._run_gbm(_BASE_INPUTS, n_sims=200, seed=1, compare_garch=False)
    assert set(result.keys()) >= {"bands", "histogram", "summary"}
    assert "comparison" not in result


def test_run_gbm_with_comparison():
    result = main._run_gbm(_BASE_INPUTS, n_sims=200, seed=1, compare_garch=True)
    assert "comparison" in result
    comp = result["comparison"]
    assert comp["model"] == "gbm-garch"
    assert set(comp.keys()) >= {"bands", "histogram", "summary", "params", "model"}
    # Both calls use the same seed integer, so each simulation constructs its
    # own RNG seeded identically. The GBM result is unaffected by the GARCH
    # computation because simulate_gbm and simulate_gbm_garch each own
    # independent RNG instances.
    bare = main._run_gbm(_BASE_INPUTS, n_sims=200, seed=1, compare_garch=False)
    assert result["bands"] == bare["bands"]


def test_retirement_ignores_compare_garch():
    """compare_garch flag should be silently ignored for non-GBM models."""
    inputs = {
        "starting_balance": 100_000.0,
        "annual_contribution": 10_000.0,
        "years_to_retire": 5,
        "retirement_years": 5,
        "annual_withdrawal": 30_000.0,
        "mean_return": 0.05,
        "std_return": 0.10,
        "inflation": 0.02,
    }
    # Direct call to _run_retirement does NOT take compare_garch; the
    # dispatcher in runSimulation handles that. Just confirm the runner
    # signature stays clean.
    result = main._run_retirement(inputs, n_sims=200, seed=1)
    assert "comparison" not in result


# ----------------------- Portfolio estimation --------------------------------

def _fake_history(tickers, *, period="5y", interval="1d"):
    """Deterministic two-asset price history (no network)."""
    rng = np.random.default_rng(0)
    n = 600
    cols = [np.cumprod(1 + rng.normal(0.0004, 0.01, n)) * 100 for _ in tickers]
    prices = np.column_stack(cols)
    dates = [f"2020-01-{(i % 28) + 1:02d}" for i in range(n)]
    return marketdata.PriceHistory(
        tickers=[t.upper() for t in tickers], prices=prices, dates=dates
    )


def test_estimate_portfolio_returns_gbm_inputs(monkeypatch):
    monkeypatch.setattr(marketdata, "fetch_price_history", _fake_history)
    result = main._estimate_portfolio({"tickers": ["aapl", "msft"]})
    assert set(result.keys()) >= {
        "mu", "sigma", "weights", "assets", "correlation",
        "tickers", "start_date", "end_date",
    }
    assert result["tickers"] == ["AAPL", "MSFT"]
    assert result["sigma"] > 0
    assert len(result["assets"]) == 2
    assert result["weights"] == pytest.approx([0.5, 0.5])


def test_estimate_portfolio_rejects_empty_tickers(monkeypatch):
    monkeypatch.setattr(marketdata, "fetch_price_history", _fake_history)
    with pytest.raises(ValueError):
        main._estimate_portfolio({"tickers": []})


def test_estimate_portfolio_validates_period(monkeypatch):
    monkeypatch.setattr(marketdata, "fetch_price_history", _fake_history)
    with pytest.raises(ValueError):
        main._estimate_portfolio({"tickers": ["AAPL"], "period": "3d"})


def test_estimate_portfolio_propagates_weights(monkeypatch):
    monkeypatch.setattr(marketdata, "fetch_price_history", _fake_history)
    result = main._estimate_portfolio(
        {"tickers": ["AAPL", "MSFT"], "weights": [3, 1]}
    )
    assert result["weights"] == pytest.approx([0.75, 0.25])


# ----------------------- Quote fetch -----------------------------------------

def _fake_quotes(tickers, *, period="5d"):
    return {
        "quotes": {t.upper(): {"price": 100.0, "as_of": "2026-06-03"}
                   for t in tickers},
        "missing": [],
    }


def test_fetch_quotes_returns_prices(monkeypatch):
    monkeypatch.setattr(marketdata, "fetch_quotes", _fake_quotes)
    out = main._fetch_quotes({"tickers": ["aapl", "msft"]})
    assert out["quotes"]["AAPL"]["price"] == 100.0
    assert out["missing"] == []


def test_fetch_quotes_rejects_empty(monkeypatch):
    monkeypatch.setattr(marketdata, "fetch_quotes", _fake_quotes)
    with pytest.raises(ValueError):
        main._fetch_quotes({"tickers": []})


def test_fetch_quotes_enforces_cap(monkeypatch):
    monkeypatch.setattr(marketdata, "fetch_quotes", _fake_quotes)
    too_many = [f"T{i}" for i in range(main.MAX_QUOTE_TICKERS + 1)]
    with pytest.raises(ValueError):
        main._fetch_quotes({"tickers": too_many})
