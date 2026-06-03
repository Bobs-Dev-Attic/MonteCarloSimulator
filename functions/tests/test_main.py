"""Tests for the request-shape behavior of main._run_gbm.

Exercises the pure-Python runner directly rather than the wrapped
firebase_functions callable.
"""

from __future__ import annotations

import main


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
