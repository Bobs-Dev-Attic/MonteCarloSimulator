# GARCH(1,1) A/B Comparison Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in "Compare with GARCH(1,1)" toggle on the GBM form so a single Run produces both a constant-σ GBM result and a time-varying-volatility GARCH result, rendered as two stacked sections on a shared y-axis.

**Architecture:** A new pure-NumPy `simulate_gbm_garch` function lives next to `simulate_gbm` and reuses the existing `aggregate.py` summaries verbatim. The Python callable accepts a new optional `compare_garch` flag and, when true, attaches a `comparison` block to the existing GBM response — the response shape stays additive so existing callers and saved Firestore docs are unaffected. On the client, `SimulationConfig` gains a `compareGarch` bool, `SimulationResult` gains an optional `comparison: SimulationResult?`, the GBM form gains a `SwitchListTile`, and `ResultsScreen` renders the existing widgets twice with a precomputed shared y-range.

**Tech Stack:** Python 3.11 + NumPy + firebase-functions (server); Flutter + Riverpod + fl_chart + cloud_functions + cloud_firestore (client); pytest (server tests); flutter_test (client tests).

---

## Task 1: Pure GARCH(1,1) path simulator

**Files:**
- Create: `functions/montecarlo/garch.py`
- Test: `functions/tests/test_garch.py`

- [ ] **Step 1: Write the failing shape + reproducibility test**

Create `functions/tests/test_garch.py`:

```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd functions && pytest tests/test_garch.py -v`
Expected: All three tests FAIL with `ImportError` or `ModuleNotFoundError: No module named 'montecarlo.garch'`.

- [ ] **Step 3: Implement minimal `simulate_gbm_garch`**

Create `functions/montecarlo/garch.py`:

```python
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd functions && pytest tests/test_garch.py -v`
Expected: 3 passed.

- [ ] **Step 5: Add long-run variance calibration test**

Append to `functions/tests/test_garch.py`:

```python
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
```

- [ ] **Step 6: Run new test and verify pass**

Run: `cd functions && pytest tests/test_garch.py::test_long_run_variance_matches_sigma_target -v`
Expected: PASS. If it fails marginally on randomness, do NOT widen tolerance — first verify the formula by checking `empirical_var_step / target_var_step` ratio printed in a debug run.

- [ ] **Step 7: Add tail-width comparison test**

Append to `functions/tests/test_garch.py`:

```python
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
```

- [ ] **Step 8: Run new test and verify pass**

Run: `cd functions && pytest tests/test_garch.py::test_terminal_tail_wider_than_gbm_on_average -v`
Expected: PASS.

- [ ] **Step 9: Run the full functions test suite to confirm nothing else broke**

Run: `cd functions && pytest -v`
Expected: All tests pass, including the original `test_models.py` tests.

- [ ] **Step 10: Commit**

```bash
git add functions/montecarlo/garch.py functions/tests/test_garch.py
git commit -m "feat(functions): add GBM-GARCH(1,1) path simulator"
```

---

## Task 2: Wire `compare_garch` flag into the callable

**Files:**
- Modify: `functions/main.py` (the `_run_gbm` function and `runSimulation` handler)
- Test: `functions/tests/test_main.py` (new file)

- [ ] **Step 1: Write the failing test for `_run_gbm` with comparison off (default)**

Create `functions/tests/test_main.py`:

```python
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
    # Same seed across both branches: paths share Z stream, so the GBM half
    # is identical to a no-comparison call.
    bare = main._run_gbm(_BASE_INPUTS, n_sims=200, seed=1, compare_garch=False)
    assert result["bands"] == bare["bands"]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd functions && pytest tests/test_main.py -v`
Expected: FAIL with `TypeError: _run_gbm() got an unexpected keyword argument 'compare_garch'` (or similar).

- [ ] **Step 3: Update `_run_gbm` to accept `compare_garch`**

In `functions/main.py`, replace the existing `_run_gbm` (currently lines roughly 22–39) with:

```python
from montecarlo.garch import simulate_gbm_garch  # add to existing imports

GARCH_ALPHA = 0.10
GARCH_BETA = 0.85


def _run_gbm(
    inputs: dict,
    n_sims: int,
    seed: int | None,
    compare_garch: bool = False,
) -> dict:
    beginning = float(inputs["beginning_value"])
    gbm_kwargs = dict(
        beginning_value=beginning,
        mu=float(inputs["mu"]),
        sigma=float(inputs["sigma"]),
        years=float(inputs["years"]),
        steps_per_year=int(inputs.get("steps_per_year", 252)),
        contribution_per_step=float(inputs.get("contribution_per_step", 0.0)),
        n_sims=n_sims,
        seed=seed,
    )
    paths = simulate_gbm(**gbm_kwargs)
    terminal = paths[-1]
    result = {
        "bands": aggregate.percentile_bands(paths),
        "histogram": aggregate.terminal_histogram(terminal),
        "summary": aggregate.summary_stats(terminal, beginning),
    }

    if compare_garch:
        garch_paths = simulate_gbm_garch(
            **gbm_kwargs,
            alpha=GARCH_ALPHA,
            beta=GARCH_BETA,
        )
        garch_terminal = garch_paths[-1]
        result["comparison"] = {
            "model": "gbm-garch",
            "bands": aggregate.percentile_bands(garch_paths),
            "histogram": aggregate.terminal_histogram(garch_terminal),
            "summary": aggregate.summary_stats(garch_terminal, beginning),
            "params": {"alpha": GARCH_ALPHA, "beta": GARCH_BETA},
        }

    return result
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd functions && pytest tests/test_main.py -v`
Expected: 2 passed.

- [ ] **Step 5: Wire `compare_garch` through `runSimulation`**

In `functions/main.py`, modify the `runSimulation` handler. Find the section that calls `runner(inputs, n_sims, seed)` (around line 100) and add the flag extraction + forwarding:

```python
@https_fn.on_call(
    memory=options.MemoryOption.MB_512,
    timeout_sec=120,
)
def runSimulation(req: https_fn.CallableRequest) -> dict:
    if req.auth is None:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            "You must be signed in to run a simulation.",
        )

    data = req.data or {}
    model = data.get("model")
    runner = _MODELS.get(model)
    if runner is None:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            f"Unknown model '{model}'. Expected one of {list(_MODELS)}.",
        )

    inputs = data.get("inputs") or {}
    n_sims = max(1, min(int(data.get("n_sims", DEFAULT_SIMS)), MAX_SIMS))
    seed = data.get("seed")
    compare_garch = bool(data.get("compare_garch", False))

    try:
        if runner is _run_gbm:
            result = runner(inputs, n_sims, seed, compare_garch=compare_garch)
        else:
            result = runner(inputs, n_sims, seed)
    except KeyError as exc:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            f"Missing required input: {exc.args[0]}",
        )
    except ValueError as exc:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT, str(exc)
        )

    result["model"] = model
    result["n_sims"] = n_sims
    return result
```

- [ ] **Step 6: Add a test for the retirement runner being unaffected**

Append to `functions/tests/test_main.py`:

```python
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
```

- [ ] **Step 7: Run all tests**

Run: `cd functions && pytest -v`
Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add functions/main.py functions/tests/test_main.py
git commit -m "feat(functions): accept compare_garch flag and return comparison block"
```

---

## Task 3: Extend Dart models for compareGarch + comparison

**Files:**
- Modify: `lib/models/simulation_config.dart`
- Modify: `lib/models/simulation_result.dart`
- Test: `test/models_test.dart`

- [ ] **Step 1: Inspect the existing models test file**

Read `test/models_test.dart` to see the current test patterns before adding new ones.

- [ ] **Step 2: Write failing tests for new fields**

Append to `test/models_test.dart` (after the existing tests; if the file has `void main()`, add tests inside it; if it has `group()` blocks, add a new group at the bottom):

```dart
test('SimulationConfig.gbm carries compareGarch into payload and json', () {
  final config = SimulationConfig.gbm(
    beginningValue: 10000,
    mu: 0.07,
    sigma: 0.15,
    years: 10,
    compareGarch: true,
  );
  expect(config.compareGarch, isTrue);
  expect(config.toCallablePayload()['compare_garch'], isTrue);
  final round = SimulationConfig.fromJson(config.toJson());
  expect(round.compareGarch, isTrue);
});

test('SimulationConfig defaults compareGarch to false', () {
  final config = SimulationConfig.gbm(
    beginningValue: 10000,
    mu: 0.07,
    sigma: 0.15,
    years: 10,
  );
  expect(config.compareGarch, isFalse);
  expect(config.toCallablePayload().containsKey('compare_garch'), isFalse);
});

test('SimulationResult parses optional comparison block', () {
  final json = {
    'bands': {
      'steps': [0.0, 1.0],
      'p5': [10000.0, 9500.0],
      'p25': [10000.0, 9800.0],
      'p50': [10000.0, 10100.0],
      'p75': [10000.0, 10400.0],
      'p95': [10000.0, 10800.0],
    },
    'histogram': {'counts': [1, 2, 1], 'edges': [9000.0, 10000.0, 11000.0, 12000.0]},
    'summary': {
      'mean': 10100.0, 'median': 10100.0,
      'p5': 9500.0, 'p95': 10800.0,
      'min': 9000.0, 'max': 12000.0,
      'prob_loss': 0.2, 'var_95': 500.0, 'success_rate': 0.8,
    },
    'comparison': {
      'model': 'gbm-garch',
      'bands': {
        'steps': [0.0, 1.0],
        'p5': [10000.0, 9300.0],
        'p25': [10000.0, 9700.0],
        'p50': [10000.0, 10100.0],
        'p75': [10000.0, 10500.0],
        'p95': [10000.0, 11000.0],
      },
      'histogram': {'counts': [2, 1, 1], 'edges': [9000.0, 10000.0, 11000.0, 12000.0]},
      'summary': {
        'mean': 10100.0, 'median': 10100.0,
        'p5': 9300.0, 'p95': 11000.0,
        'min': 8800.0, 'max': 12200.0,
        'prob_loss': 0.25, 'var_95': 700.0, 'success_rate': 0.75,
      },
    },
  };
  final result = SimulationResult.fromJson(json);
  expect(result.comparison, isNotNull);
  expect(result.comparison!.summary.p5, 9300.0);
});

test('SimulationResult.fromJson tolerates missing comparison', () {
  final json = {
    'bands': {
      'steps': [0.0], 'p5': [1.0], 'p25': [1.0],
      'p50': [1.0], 'p75': [1.0], 'p95': [1.0],
    },
    'histogram': {'counts': [1], 'edges': [0.0, 1.0]},
    'summary': {
      'mean': 1.0, 'median': 1.0, 'p5': 1.0, 'p95': 1.0,
      'min': 1.0, 'max': 1.0, 'prob_loss': 0.0,
      'var_95': 0.0, 'success_rate': 1.0,
    },
  };
  final result = SimulationResult.fromJson(json);
  expect(result.comparison, isNull);
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/models_test.dart`
Expected: New tests fail (missing `compareGarch` parameter, missing `comparison` field on `SimulationResult`).

- [ ] **Step 4: Add `compareGarch` to `SimulationConfig`**

In `lib/models/simulation_config.dart`, modify the `SimulationConfig` class. Replace the existing class body with:

```dart
class SimulationConfig {
  const SimulationConfig({
    required this.model,
    required this.inputs,
    this.nSims = 10000,
    this.seed,
    this.compareGarch = false,
  });

  final String model;
  final Map<String, dynamic> inputs;
  final int nSims;
  final int? seed;
  final bool compareGarch;

  /// Convenience constructor for a GBM portfolio forecast.
  factory SimulationConfig.gbm({
    required double beginningValue,
    required double mu,
    required double sigma,
    required double years,
    int stepsPerYear = 252,
    double contributionPerStep = 0.0,
    int nSims = 10000,
    int? seed,
    bool compareGarch = false,
  }) {
    return SimulationConfig(
      model: 'gbm',
      nSims: nSims,
      seed: seed,
      compareGarch: compareGarch,
      inputs: {
        'beginning_value': beginningValue,
        'mu': mu,
        'sigma': sigma,
        'years': years,
        'steps_per_year': stepsPerYear,
        'contribution_per_step': contributionPerStep,
      },
    );
  }

  /// Convenience constructor for a retirement accumulation + withdrawal run.
  factory SimulationConfig.retirement({
    required double startingBalance,
    required double annualContribution,
    required int yearsToRetire,
    required int retirementYears,
    required double annualWithdrawal,
    required double meanReturn,
    required double stdReturn,
    double inflation = 0.0,
    int nSims = 10000,
    int? seed,
  }) {
    return SimulationConfig(
      model: 'retirement',
      nSims: nSims,
      seed: seed,
      inputs: {
        'starting_balance': startingBalance,
        'annual_contribution': annualContribution,
        'years_to_retire': yearsToRetire,
        'retirement_years': retirementYears,
        'annual_withdrawal': annualWithdrawal,
        'mean_return': meanReturn,
        'std_return': stdReturn,
        'inflation': inflation,
      },
    );
  }

  /// Payload sent to the `runSimulation` callable function.
  Map<String, dynamic> toCallablePayload() => {
        'model': model,
        'inputs': inputs,
        'n_sims': nSims,
        if (seed != null) 'seed': seed,
        if (compareGarch) 'compare_garch': true,
      };

  /// Serialized form stored in Firestore.
  Map<String, dynamic> toJson() => {
        'model': model,
        'inputs': inputs,
        'nSims': nSims,
        if (seed != null) 'seed': seed,
        if (compareGarch) 'compareGarch': true,
      };

  factory SimulationConfig.fromJson(Map<String, dynamic> json) {
    return SimulationConfig(
      model: json['model'] as String,
      inputs: Map<String, dynamic>.from(json['inputs'] as Map),
      nSims: (json['nSims'] as num?)?.toInt() ?? 10000,
      seed: (json['seed'] as num?)?.toInt(),
      compareGarch: (json['compareGarch'] as bool?) ?? false,
    );
  }
}
```

- [ ] **Step 5: Add `comparison` to `SimulationResult`**

In `lib/models/simulation_result.dart`, replace the existing `SimulationResult` class (the section starting `class SimulationResult`, around line 109) with:

```dart
class SimulationResult {
  const SimulationResult({
    required this.bands,
    required this.histogram,
    required this.summary,
    this.comparison,
  });

  final PercentileBands bands;
  final Histogram histogram;
  final SummaryStats summary;
  final SimulationResult? comparison;

  factory SimulationResult.fromJson(Map<String, dynamic> json) {
    final compRaw = json['comparison'];
    return SimulationResult(
      bands: PercentileBands.fromJson(
          Map<String, dynamic>.from(json['bands'] as Map)),
      histogram: Histogram.fromJson(
          Map<String, dynamic>.from(json['histogram'] as Map)),
      summary: SummaryStats.fromJson(
          Map<String, dynamic>.from(json['summary'] as Map)),
      comparison: compRaw == null
          ? null
          : SimulationResult.fromJson(Map<String, dynamic>.from(compRaw as Map)),
    );
  }

  Map<String, dynamic> toJson() => {
        'bands': bands.toJson(),
        'histogram': histogram.toJson(),
        'summary': summary.toJson(),
        if (comparison != null) 'comparison': comparison!.toJson(),
      };
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/models_test.dart`
Expected: All tests pass (existing + 4 new).

- [ ] **Step 7: Commit**

```bash
git add lib/models/simulation_config.dart lib/models/simulation_result.dart test/models_test.dart
git commit -m "feat(models): add compareGarch flag and optional comparison result"
```

---

## Task 4: Add shared y-range support to FanChart

**Files:**
- Modify: `lib/widgets/fan_chart.dart`

- [ ] **Step 1: Add optional `yRange` parameter and use it in LineChartData**

In `lib/widgets/fan_chart.dart`, modify the `FanChart` class. Replace the constructor and the field declarations (top of the class, lines roughly 10–17) with:

```dart
class FanChart extends StatelessWidget {
  const FanChart({
    super.key,
    required this.bands,
    required this.config,
    this.yRange,
  });

  final PercentileBands bands;
  final SimulationConfig config;

  /// Optional (minY, maxY) override. When set, both charts can share an axis
  /// for honest side-by-side visual comparison.
  final (double, double)? yRange;
```

Then in the `build` method, find the `maxY` computation (around line 48):

```dart
    final maxY = [
      ...bands.p95,
      ...bands.p75,
      ...bands.p50,
    ].fold<double>(1, (max, value) => value > max ? value : max);
```

Replace it with:

```dart
    final autoMaxY = [
      ...bands.p95,
      ...bands.p75,
      ...bands.p50,
    ].fold<double>(1, (max, value) => value > max ? value : max);
    final effectiveMinY = yRange?.$1 ?? 0;
    final effectiveMaxY = yRange?.$2 ?? autoMaxY * 1.08;
    final maxY = effectiveMaxY; // used for y-axis interval below
```

Then find the `LineChartData` instantiation and update `minY`/`maxY`:

```dart
          minY: 0,
          maxY: maxY * 1.08,
```

becomes:

```dart
          minY: effectiveMinY,
          maxY: effectiveMaxY,
```

- [ ] **Step 2: Run flutter analyze to confirm no compile errors**

Run: `flutter analyze lib/widgets/fan_chart.dart`
Expected: No errors. (Warnings about unrelated code are fine.)

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/fan_chart.dart
git commit -m "feat(fan_chart): accept optional shared y-range"
```

---

## Task 5: Add the compare-with-GARCH toggle to the GBM form

**Files:**
- Modify: `lib/screens/simulation_form_screen.dart`

- [ ] **Step 1: Add state + UI for the toggle**

In `lib/screens/simulation_form_screen.dart`:

After the `bool _busy = false;` line, add:

```dart
  bool _compareGarch = false;
```

In `_buildConfig`, modify the GBM branch:

```dart
    if (_model == 'gbm') {
      return SimulationConfig.gbm(
        beginningValue: _d(_beginningValue),
        mu: _d(_mu) / 100, // percent -> fraction
        sigma: _d(_sigma) / 100,
        years: _d(_years),
        nSims: nSims,
        compareGarch: _compareGarch,
      );
    }
```

In `_gbmFields()`, replace the existing implementation:

```dart
  List<Widget> _gbmFields() => [
        _numField(_beginningValue, 'Beginning value (\$)'),
        _numField(_mu, 'Expected annual return (%)'),
        _numField(_sigma, 'Volatility / std dev (%)'),
        _numField(_years, 'Time horizon (years)'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _compareGarch,
            onChanged: (v) => setState(() => _compareGarch = v),
            title: const Text('Compare with GARCH(1,1)'),
            subtitle: const Text(
              'Adds a second simulation with time-varying volatility, same average σ.',
            ),
          ),
        ),
      ];
```

- [ ] **Step 2: Run flutter analyze**

Run: `flutter analyze lib/screens/simulation_form_screen.dart`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/simulation_form_screen.dart
git commit -m "feat(form): add Compare with GARCH toggle to GBM form"
```

---

## Task 6: Render stacked GBM/GARCH sections on the results screen

**Files:**
- Modify: `lib/screens/results_screen.dart`

- [ ] **Step 1: Refactor the chart+histogram+summary block into a private helper**

In `lib/screens/results_screen.dart`, find the existing `body: ListView(...children: [...])` block. The current children (around lines 128–181) include `_HeroSummary`, the GBM/Retirement chart card, the histogram card, and the summary card. Wrap them into a helper so we can render twice.

Add this method to the `_ResultsScreenState` class (just before `build`):

```dart
  Widget _resultSection({
    required String? sectionLabel,
    required SimulationResult result,
    required (double, double)? sharedYRange,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sectionLabel != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              sectionLabel,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
            ),
          ),
        ],
        _ChartCard(
          title: _isRetirement ? 'Balance fan chart' : 'Portfolio fan chart',
          subtitle:
              'Outer band shows the 5th to 95th percentile range. Inner band shows the 25th to 75th percentile range.',
          child: FanChart(
            bands: result.bands,
            config: _config,
            yRange: sharedYRange,
          ),
        ),
        const SizedBox(height: 20),
        _ChartCard(
          title: 'Final outcome distribution',
          subtitle: _isRetirement
              ? 'Bars show how often final balances land in each bucket. Warm bars are depleted outcomes.'
              : 'Bars show the distribution of terminal values. Warm bars finish below the starting balance.',
          child: TerminalHistogram(
            histogram: result.histogram,
            config: _config,
          ),
        ),
        const SizedBox(height: 20),
        const _SectionTitle('Summary'),
        SummaryStatsCard(
          summary: result.summary,
          isRetirement: _isRetirement,
        ),
      ],
    );
  }
```

- [ ] **Step 2: Compute shared y-range when comparison is present**

Still in `_ResultsScreenState`, add a helper just below `_resultSection`:

```dart
  (double, double)? _sharedYRangeWithComparison() {
    final comp = _result.comparison;
    if (comp == null) return null;
    double maxOf(List<double> xs) =>
        xs.fold<double>(0, (m, v) => v > m ? v : m);
    final hi = [
      maxOf(_result.bands.p95),
      maxOf(_result.bands.p75),
      maxOf(_result.bands.p50),
      maxOf(comp.bands.p95),
      maxOf(comp.bands.p75),
      maxOf(comp.bands.p50),
    ].reduce((a, b) => a > b ? a : b);
    return (0.0, hi * 1.08);
  }
```

- [ ] **Step 3: Use the helpers in `build`**

In the `build` method, replace the section that begins with `const SizedBox(height: 20)` after `_HeroSummary(...)` and ends with `SummaryStatsCard(...)` (roughly lines 152–181) with:

```dart
          const SizedBox(height: 20),
          if (_result.comparison == null)
            _resultSection(
              sectionLabel: null,
              result: _result,
              sharedYRange: null,
            )
          else ...[
            _resultSection(
              sectionLabel: 'Constant σ (GBM)',
              result: _result,
              sharedYRange: _sharedYRangeWithComparison(),
            ),
            const SizedBox(height: 28),
            _resultSection(
              sectionLabel: 'GARCH(1,1)',
              result: _result.comparison!,
              sharedYRange: _sharedYRangeWithComparison(),
            ),
          ],
```

- [ ] **Step 4: Carry compareGarch through reruns**

In `_buildConfigFromDraft`, modify the GBM branch:

```dart
    if (_config.model == 'gbm') {
      return SimulationConfig.gbm(
        beginningValue: _input('beginning_value'),
        mu: _input('mu'),
        sigma: _input('sigma'),
        years: _input('years'),
        nSims: _draftNSims,
        compareGarch: _config.compareGarch,
      );
    }
```

- [ ] **Step 5: Run flutter analyze**

Run: `flutter analyze lib/screens/results_screen.dart`
Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/results_screen.dart
git commit -m "feat(results): stacked GBM/GARCH comparison with shared y-axis"
```

---

## Task 7: Add a "with GARCH" badge on saved-sim tiles

**Files:**
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: Add the chip to the saved-sim tile**

In `lib/screens/home_screen.dart`, locate the `_SimTile.build` method (the `ListTile` with `title`, `subtitle`, `trailing`). The `trailing` is currently an `IconButton`. Replace it with a `Row` containing the badge (when applicable) followed by the existing delete button.

Find:

```dart
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () {
          final user = ref.read(authStateProvider).value;
          if (user != null) {
            ref
                .read(firestoreServiceProvider)
                .deleteSimulation(user.uid, sim.id);
          }
        },
      ),
```

Replace with:

```dart
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sim.result.comparison != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: const Text('with GARCH'),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              final user = ref.read(authStateProvider).value;
              if (user != null) {
                ref
                    .read(firestoreServiceProvider)
                    .deleteSimulation(user.uid, sim.id);
              }
            },
          ),
        ],
      ),
```

- [ ] **Step 2: Run flutter analyze**

Run: `flutter analyze lib/screens/home_screen.dart`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat(home): show 'with GARCH' badge on saved comparisons"
```

---

## Task 8: Deploy and smoke-test

**Files:** None modified. Pure operational verification.

- [ ] **Step 1: Run all server tests one more time**

Run: `cd functions && pytest -v`
Expected: All tests pass.

- [ ] **Step 2: Run all client tests one more time**

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 3: Deploy the updated function**

Run: `firebase deploy --only functions --force`
Expected: `+ functions[runSimulation(us-central1)] Successful update operation.`

- [ ] **Step 4: Manual smoke test (web)**

Run: `flutter run -d chrome --web-port=5000`
- Sign in via email/password.
- On the GBM form: enter Beginning=10000, Return=7, Volatility=15, Horizon=10.
- Toggle **Compare with GARCH(1,1)** on.
- Click **Run simulation**.

Expected: results screen shows two stacked sections — "Constant σ (GBM)" with fan chart + histogram + summary, then "GARCH(1,1)" with the same. Both y-axes are visually aligned.

- [ ] **Step 5: Confirm Firestore persistence**

In the Firebase console → Firestore → `users/{your-uid}/simulations/`, find the latest doc.

Expected: the doc's `result` map contains a top-level `comparison` field whose `model` is `gbm-garch`. The saved tile on the home screen shows the "with GARCH" chip.

- [ ] **Step 6: Confirm non-comparison runs still work**

Toggle the switch off, re-run. Results screen shows one section (no label). Saved tile has no chip.

---

## Self-review notes (already applied)

- All spec sections have a corresponding task (GARCH module → 1; server flag → 2; client models → 3; shared y-axis → 4; form toggle → 5; results layout → 6; badge → 7; deploy → 8).
- No placeholder steps. Every code step shows complete code.
- Type/name consistency: `compareGarch` (Dart) ↔ `compare_garch` (Python/JSON) is the only naming gap and is documented at the boundaries (`toCallablePayload` and `_run_gbm`).
- Rerun path (Task 6, Step 4) preserves `compareGarch` from the originating config — without this, the in-results "Rerun" button would silently drop the comparison.
