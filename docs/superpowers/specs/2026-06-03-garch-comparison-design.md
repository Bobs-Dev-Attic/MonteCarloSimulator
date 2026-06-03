# GARCH(1,1) A/B comparison mode

## Purpose

Let a user run the existing GBM portfolio simulation and, with a single
checkbox, also get a GARCH(1,1) simulation of the same scenario side by
side. The goal is for the user to *see* what time-varying volatility
adds (clustering, fatter tails on the histogram, wider mid-horizon
bands) without having to learn or supply GARCH parameters.

## Non-goals

- Exposing GARCH parameters (ω, α, β) in the UI.
- Asymmetric or multivariate GARCH (EGARCH, GJR-GARCH, DCC).
- Fitting GARCH to historical data.
- Adding GARCH to the Retirement model.

## User-facing behavior

- On the **Portfolio (GBM)** form, a new `SwitchListTile` appears below
  the σ field: **"Compare with GARCH(1,1)"**, off by default. One line
  of helper text: "Adds a second simulation with time-varying
  volatility, same average σ."
- When off, behavior is unchanged.
- When on, the **Run simulation** button triggers a single server call;
  the results screen renders **two stacked sections**:
  1. **Constant σ (GBM)** — the existing fan chart, histogram, summary stats.
  2. **GARCH(1,1)** — same widgets, same percentile bands, same
     histogram bins.
  Both charts share the same y-axis range so the comparison is honest.
- The saved Firestore document carries the comparison alongside the
  primary result. On the home screen list, saved comparisons show a
  small "with GARCH" badge.

## GARCH calibration

GARCH(1,1) on log-returns:
`σ²_t = ω + α · r²_{t-1} + β · σ²_{t-1}`

Defaults:
- `α = 0.10`, `β = 0.85` (typical equity values; together α+β = 0.95,
  giving realistic volatility persistence).
- `ω` is derived from the user's annual σ so the long-run variance
  matches: `ω = (σ_step)² · (1 − α − β)` where
  `σ_step = σ_annual / sqrt(steps_per_year)`.
- `σ²_0` (initial conditional variance) is set to the long-run variance,
  so the two simulations start with identical instantaneous volatility.

The seed is shared between both simulations so the GBM and GARCH paths
draw from the same Z stream; this gives a much cleaner visual
comparison than independent samples.

## Server design

### New module: `functions/montecarlo/garch.py`

```
def simulate_gbm_garch(
    *,
    beginning_value: float,
    mu: float,
    sigma: float,              # annual long-run volatility target
    years: float,
    steps_per_year: int = 252,
    contribution_per_step: float = 0.0,
    n_sims: int,
    seed: int | None = None,
    alpha: float = 0.10,
    beta: float = 0.85,
) -> np.ndarray:
    """Vectorized GBM with GARCH(1,1) conditional variance.

    Returns paths shaped (n_steps + 1, n_sims), same as simulate_gbm,
    so the existing aggregate functions work unchanged.
    """
```

Implementation is a per-step loop over time, vectorized across the
n_sims axis. The aggregation reuses `montecarlo/aggregate.py` as-is.

### `functions/main.py`

- Request data gains `compare_garch: bool` (default `false`). Existing
  callers are unaffected.
- `_run_gbm` returns the GBM result as before. If `compare_garch` is
  true, it additionally computes the GARCH paths (same `mu`, same
  `sigma`, same `seed`, same `n_sims`) and packs the aggregated result
  under a `"comparison"` key:
  ```
  {
    "bands": ..., "histogram": ..., "summary": ...,
    "model": "gbm", "n_sims": ...,
    "comparison": {
      "model": "gbm-garch",
      "bands": ..., "histogram": ..., "summary": ...,
      "params": {"alpha": 0.10, "beta": 0.85}
    }
  }
  ```
- `_run_retirement` is unchanged. The flag is ignored for retirement.

### Tests (`functions/tests/test_garch.py`)

- **Shape:** output matches `simulate_gbm`'s shape.
- **Reproducibility:** same seed → identical paths.
- **Long-run variance:** empirical variance of log-returns over a long
  horizon converges to `(σ_annual / sqrt(steps_per_year))²` within a
  reasonable tolerance.
- **Tail behavior:** at the simulation midpoint and end, the absolute
  P5/P95 *distance from the median* is no smaller than GBM's (using
  the same seed); typically larger. Encodes the qualitative claim
  "GARCH widens the tails relative to constant σ."

## Client design

### Data model

- `SimulationConfig` adds `bool compareGarch` (default `false`),
  serialized into the callable payload as `compare_garch`.
- `SimulationResult` adds `SimulationResult? comparison`. When present,
  `comparison.model == 'gbm-garch'`.
- Firestore document schema gains a top-level `comparison` field that
  mirrors `SimulationResult.toJson()` for the comparison block.

### Form (`simulation_form_screen.dart`)

- New `SwitchListTile` widget between the σ field and the "Time
  horizon" field, only visible on the GBM tab.
- The checkbox state lives in form state and feeds `_buildConfig()`.

### Results (`results_screen.dart`)

- Existing single-section layout is refactored into a private
  `_ResultSection({required String label, required SimulationResult
  result, required (double, double) sharedYRange})` widget.
- If `widget.result.comparison == null`, render one section with the
  existing label.
- Otherwise compute the shared y-axis range as
  `(min(both.bands.p5.min), max(both.bands.p95.max))` and render
  two sections labeled "Constant σ (GBM)" and "GARCH(1,1)".
- The `FanChart` widget gains an optional `(double, double) yRange`
  parameter; when set, both fl_chart `LineChartData.minY` /`maxY` use
  it instead of auto-scaling.

### Home screen list

- Each saved-simulation tile already shows model + horizon. When the
  saved doc has a non-null `comparison`, append a `Chip("with GARCH")`
  to the trailing area.

## Risks and open questions

- **GARCH per-step loop performance.** GBM is fully vectorized in one
  numpy call; GARCH has a sequential dependency over time so it's a
  Python-level loop over n_steps with vectorization across n_sims.
  For `years=30, steps_per_year=252, n_sims=10_000` that's 7,560
  iterations of `O(n_sims)` numpy ops — well within the 120s callable
  timeout but worth measuring. If it's slow we can drop
  `steps_per_year` to 52 (weekly) for GARCH only.
- **Shared seed correctness.** Sharing the Z stream is desirable for
  visual comparison but means the two distributions are correlated, not
  independent. That is intentional and called out in this spec; the
  comparison is "what does the same shock sequence look like under
  constant vs clustering volatility," not "draw two independent samples
  and compare distributions."
- **Saved-doc backwards compatibility.** Existing saved sims have no
  `comparison` field; the parser must treat missing as null. Mark
  explicitly in `SimulationResult.fromJson`.
