# Portfolio builder with yfinance-derived μ/σ — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an advisor build a GBM portfolio from real tickers and have the
server derive μ/σ (and the diversification benefit) from historical prices via
yfinance, then drop those into the existing simulation — with manual μ/σ intact
as the default and the fallback.

**Architecture:** A pure-NumPy `estimate.py` turns a price matrix into GBM
inputs; a thin, lazily-imported `marketdata.py` is the *only* networked module
(yfinance → aligned `PriceHistory`). A new `estimatePortfolio` callable wires
them together and returns μ/σ + per-asset stats + correlation; `runSimulation`
is untouched, so estimation and simulation stay decoupled. The client adds a
"Build from tickers" panel on the GBM form that fills the μ/σ fields from the
estimate and degrades gracefully when Yahoo is unavailable.

**Tech Stack:** Python 3.11 + NumPy + pandas + yfinance + firebase-functions
(server); Flutter + Riverpod + cloud_functions + cloud_firestore (client);
pytest (server tests); flutter_test (client tests).

---

## Task 1: Pure price → GBM-inputs estimator  ✅ DONE

**Files:** `functions/montecarlo/estimate.py`, `functions/tests/test_estimate.py`

- [x] `log_returns`, `annualized_asset_stats`, `correlation_matrix`,
  `portfolio_gbm_inputs` implemented as pure NumPy.
- [x] Tests recover known μ/σ from a long synthetic GBM series, verify the
  diversification benefit (portfolio σ < weighted-average σ), weight
  normalization, and input validation. `pytest tests/test_estimate.py` → 12 passed.
- [x] Committed.

## Task 2: Isolated yfinance market-data fetch  ✅ DONE

**Files:** `functions/montecarlo/marketdata.py`, `functions/tests/test_marketdata.py`, `functions/requirements.txt`

- [x] `PriceHistory` dataclass + `fetch_price_history` (lazy yfinance import,
  `MarketDataError` on any failure) + `_frame_to_history` parser (handles flat
  single-ticker and MultiIndex multi-ticker frames; drops gap rows).
- [x] Tests drive `_frame_to_history` with synthetic pandas frames (no network)
  → 6 passed. `requirements.txt` gains `yfinance`, `pandas`.
- [x] Committed.
- [ ] **Live verification (post-deploy only):** in a networked/deployed env,
  `python -c "from montecarlo.marketdata import fetch_price_history as f; print(f(['AAPL','MSFT']).prices.shape)"`
  returns a non-trivial shape. Cannot run in the allowlisted sandbox.

## Task 3: `estimatePortfolio` callable  ✅ DONE

**Files:** `functions/main.py`, `functions/tests/test_main.py`

- [x] `_estimate_portfolio(inputs)` pure runner + `estimatePortfolio` callable
  (auth-gated; validates ticker count/period/interval; maps `ValueError` →
  `INVALID_ARGUMENT`, `MarketDataError` → `UNAVAILABLE`).
- [x] Tests monkeypatch `marketdata.fetch_price_history` to assert shape,
  weight propagation, and validation. Full suite `pytest` → all passed.
- [x] Committed.

---

## Task 4: Client models + service  ⬜ TODO

**Files:** `lib/models/portfolio.dart` (new), `lib/services/portfolio_service.dart` (new), `lib/state/providers.dart`, `test/portfolio_test.dart` (new)

- [ ] **Step 1:** Add `PortfolioHolding({String ticker, double weight})` and a
  `Portfolio` wrapper with `toCallablePayload()` →
  `{tickers: [...], weights: [...], period}`. Add `PortfolioEstimate.fromJson`
  parsing `mu`, `sigma`, `assets`, `correlation`, `tickers`, `start_date`,
  `end_date`.
- [ ] **Step 2:** Failing tests in `test/portfolio_test.dart` for payload
  shape, weight defaulting, and estimate parsing. Run `flutter test test/portfolio_test.dart` → fail.
- [ ] **Step 3:** Implement until green.
- [ ] **Step 4:** `PortfolioService.estimate(holdings, {period})` calls the
  `estimatePortfolio` callable (mirror `SimulationService.run`); add
  `portfolioServiceProvider` to `providers.dart`.
- [ ] **Step 5:** `flutter analyze` clean; commit
  `feat(models): Portfolio + PortfolioEstimate and PortfolioService`.

## Task 5: "Build from tickers" panel on the GBM form  ⬜ TODO

**Files:** `lib/screens/simulation_form_screen.dart`

- [ ] **Step 1:** Add an `ExpansionTile` above the μ/σ fields (GBM tab only):
  editable ticker/weight rows, a period dropdown (`1y/2y/5y/10y`), and an
  **Estimate from history** button with a busy spinner.
- [ ] **Step 2:** On success, set `_mu`/`_sigma` from the estimate (convert to
  the form's percent units), show a caption "from history: AAPL, MSFT · 5y",
  and keep the fields editable.
- [ ] **Step 3:** On `UNAVAILABLE` (or any error), show a non-blocking SnackBar
  and leave manual entry usable. Never block the **Run simulation** button.
- [ ] **Step 4:** `flutter analyze` clean; commit
  `feat(form): build GBM portfolio from tickers via yfinance estimate`.

## Task 6: Provenance on saved sims  ⬜ TODO

**Files:** `lib/models/simulation_config.dart` (optional `sourcePortfolio`), `lib/screens/results_screen.dart`, `lib/screens/home_screen.dart`

- [ ] **Step 1:** When a run was seeded from an estimate, attach the source
  portfolio (tickers + weights + window) to the saved Firestore doc
  (additive/back-compatible; missing → null).
- [ ] **Step 2:** Results screen shows a "Derived from <tickers> (<window>)"
  line; home-screen tile shows a small "from tickers" chip.
- [ ] **Step 3:** Tests for back-compatible parse; `flutter analyze`; commit.

## Task 7: Server-side caching  ✅ DONE (verified)

**Files:** `functions/montecarlo/cache.py`, `functions/tests/test_cache.py`, `functions/main.py`

- [x] `cache.py`: `make_key` (stable hash), `InMemoryStore`/`FirestoreStore`,
  and `cached_fetch` (fresh-hit / expired-refetch / **stale-on-failure** /
  propagate non-`MarketDataError`). 8 tests, all passing.
- [x] Wired into both callables: `estimatePortfolio` caches per
  `(tickers, weights, period, interval)` for 12h; `fetchQuotes` per sorted
  tickers for 15m. Store is a lazily-built `marketDataCache` Firestore
  collection (deferred so imports/tests don't need Firestore).
- [x] Client surfaces the `stale` flag (`QuotesResult.stale` →
  "Prices may be delayed (cached)" note).

---

## Task 8: Deploy and smoke-test  ⬜ TODO

- [ ] `cd functions && pytest -v` → all pass.
- [ ] `flutter test` → all pass.
- [ ] Confirm the function's network policy permits `*.finance.yahoo.com`.
- [ ] `firebase deploy --only functions` deploys `estimatePortfolio`.
- [ ] Manual: GBM form → add `VTI` 0.6 / `BND` 0.4 → **Estimate from history**
  → μ/σ populate → **Run simulation** → results render. Then break the network
  / use a bogus ticker and confirm the manual-fallback SnackBar path.

---

## Status summary

- **Done (server foundation, fully tested offline):** Tasks 1–3. The estimation
  math and callable are verified; only the live Yahoo fetch (Task 2 live step)
  is unverifiable in the allowlisted sandbox and must be checked post-deploy.
- **Remaining:** client UI (4–6), optional caching (7), deploy/smoke (8).
