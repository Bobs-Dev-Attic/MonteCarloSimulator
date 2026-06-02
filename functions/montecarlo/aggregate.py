"""Aggregate raw Monte Carlo paths into compact, device-friendly summaries.

Sending 10,000 raw paths to a phone is pointless. Instead we return:
  * percentile bands over time (drives a "fan chart"),
  * a histogram of terminal values (the log-normal distribution of outcomes),
  * scalar summary statistics (median, probability of loss, VaR, success rate).
All values are plain Python types so the result serializes straight to JSON /
Firestore.
"""

from __future__ import annotations

import numpy as np

PERCENTILES = [5, 25, 50, 75, 95]


def downsample_indices(n_points: int, max_points: int = 120) -> np.ndarray:
    """Evenly spaced indices (always including first and last) for the chart."""
    if n_points <= max_points:
        return np.arange(n_points)
    return np.unique(np.linspace(0, n_points - 1, max_points).astype(int))


def percentile_bands(paths: np.ndarray, max_points: int = 120) -> dict:
    """Percentile bands at each (downsampled) time step for a fan chart."""
    idx = downsample_indices(paths.shape[0], max_points)
    pct = np.percentile(paths[idx], PERCENTILES, axis=1)
    return {
        "steps": idx.tolist(),
        "p5": pct[0].tolist(),
        "p25": pct[1].tolist(),
        "p50": pct[2].tolist(),
        "p75": pct[3].tolist(),
        "p95": pct[4].tolist(),
    }


def terminal_histogram(terminal_values: np.ndarray, bins: int = 40) -> dict:
    """Histogram (counts + bin edges) of final outcomes."""
    counts, edges = np.histogram(np.asarray(terminal_values, dtype=float), bins=bins)
    return {"counts": counts.tolist(), "edges": edges.tolist()}


def summary_stats(
    terminal_values: np.ndarray,
    beginning_value: float,
    success_threshold: float = 0.0,
) -> dict:
    """Scalar risk/return statistics from the terminal value distribution.

    Args:
        terminal_values: Final value of every simulated path.
        beginning_value: Reference value used for probability-of-loss and VaR.
        success_threshold: A path "succeeds" if its terminal value exceeds this
            (0 for a retirement run => didn't run out of money).
    """
    tv = np.asarray(terminal_values, dtype=float)
    p5 = float(np.percentile(tv, 5))
    return {
        "mean": float(np.mean(tv)),
        "median": float(np.median(tv)),
        "p5": p5,
        "p95": float(np.percentile(tv, 95)),
        "min": float(np.min(tv)),
        "max": float(np.max(tv)),
        "prob_loss": float(np.mean(tv < beginning_value)),
        # 95% Value at Risk: the loss vs. starting value at the 5th percentile.
        "var_95": float(max(0.0, beginning_value - p5)),
        "success_rate": float(np.mean(tv > success_threshold)),
    }
