"""Standalone Monte Carlo prototype (NumPy + matplotlib).

Runs the same GBM and retirement models used by the Cloud Function, prints
summary statistics, and saves two plots per model:
  * the path trajectories (a sample of simulated paths + percentile bands),
  * a histogram of terminal outcomes (the log-normal distribution).

Use this to validate the math independently of any Firebase deployment.

    cd scripts && python prototype.py            # saves PNGs to scripts/out/
    python prototype.py --show                    # also display interactively
"""

from __future__ import annotations

import argparse
import os
import sys

import numpy as np

# Allow importing the shared models from ../functions without installing them.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "functions"))

import matplotlib

from montecarlo import aggregate  # noqa: E402
from montecarlo.gbm import simulate_gbm  # noqa: E402
from montecarlo.retirement import simulate_retirement, success_rate  # noqa: E402

OUT_DIR = os.path.join(os.path.dirname(__file__), "out")


def _print_summary(title: str, summary: dict) -> None:
    print(f"\n=== {title} ===")
    for k, v in summary.items():
        print(f"  {k:12s}: {v:,.4f}" if isinstance(v, float) else f"  {k:12s}: {v}")


def plot_paths_and_histogram(paths: np.ndarray, title: str, filename: str, show: bool) -> None:
    import matplotlib.pyplot as plt

    bands = aggregate.percentile_bands(paths)
    steps = np.array(bands["steps"])
    terminal = paths[-1]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 5))

    # Left: a sample of raw trajectories + median/percentile bands.
    sample = paths[:, : min(200, paths.shape[1])]
    ax1.plot(sample, color="steelblue", alpha=0.05)
    ax1.plot(steps, bands["p50"], color="black", lw=2, label="Median (p50)")
    ax1.fill_between(steps, bands["p5"], bands["p95"], color="orange", alpha=0.25,
                     label="p5–p95")
    ax1.set_title(f"{title}: trajectories")
    ax1.set_xlabel("Time step")
    ax1.set_ylabel("Value")
    ax1.legend(loc="upper left")

    # Right: histogram of terminal values (expect a log-normal-ish shape).
    ax2.hist(terminal, bins=40, color="seagreen", alpha=0.8)
    ax2.axvline(np.median(terminal), color="black", lw=2, label="Median")
    ax2.axvline(np.percentile(terminal, 5), color="red", ls="--", label="p5")
    ax2.axvline(np.percentile(terminal, 95), color="red", ls="--", label="p95")
    ax2.set_title(f"{title}: terminal value distribution")
    ax2.set_xlabel("Terminal value")
    ax2.set_ylabel("Frequency")
    ax2.legend()

    fig.tight_layout()
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, filename)
    fig.savefig(path, dpi=110)
    print(f"  saved plot -> {path}")
    if show:
        plt.show()
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--show", action="store_true", help="display plots interactively")
    parser.add_argument("--sims", type=int, default=10_000, help="number of paths")
    args = parser.parse_args()

    if not args.show:
        matplotlib.use("Agg")  # headless / file-only rendering

    # --- Model 1: GBM portfolio forecast -------------------------------------
    gbm_paths = simulate_gbm(
        beginning_value=10_000, mu=0.07, sigma=0.15, years=10,
        steps_per_year=252, n_sims=args.sims, seed=2026,
    )
    _print_summary(
        "GBM portfolio (10y, mu=7%, sigma=15%)",
        aggregate.summary_stats(gbm_paths[-1], beginning_value=10_000),
    )
    plot_paths_and_histogram(gbm_paths, "GBM portfolio", "gbm.png", args.show)

    # --- Model 2: Retirement accumulation + withdrawal -----------------------
    ret_hist = simulate_retirement(
        starting_balance=100_000, annual_contribution=15_000,
        years_to_retire=25, retirement_years=30, annual_withdrawal=60_000,
        mean_return=0.06, std_return=0.12, inflation=0.025,
        n_sims=args.sims, seed=2026,
    )
    ret_summary = aggregate.summary_stats(ret_hist[-1], beginning_value=100_000)
    ret_summary["success_rate"] = success_rate(ret_hist)
    _print_summary("Retirement (25y save, 30y draw)", ret_summary)
    print(f"  -> Probability of NOT running out of money: "
          f"{ret_summary['success_rate'] * 100:.1f}%")
    plot_paths_and_histogram(ret_hist, "Retirement", "retirement.png", args.show)


if __name__ == "__main__":
    main()
