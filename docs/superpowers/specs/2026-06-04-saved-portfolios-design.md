# Saved (model) portfolios

## Purpose

Promote the previously-stubbed **Portfolios** tab into a real feature: let an
advisor save a *named* basket of tickers + target weights under a household and
**re-simulate it on demand**. This is the reusable counterpart to the ad-hoc
"Simulate" bridge — instead of re-typing tickers each time, an advisor keeps
"60/40 Growth", "All Equity", etc. on the customer and runs any of them through
the GBM model with one tap.

The `households/{hid}/portfolios/{pid}` sub-collection (and its Firestore rule)
already existed; this fills it in.

## Distinction from the investments database

- **Investments** = what the customer *actually holds* (`ticker` + `quantity`),
  priced live for current market value.
- **Saved portfolio** = a *model allocation* (`ticker` + target `weight`) the
  advisor wants to study. No share counts, no live valuation — it exists to be
  estimated and simulated.

## Non-goals

- No live pricing/valuation of a saved portfolio (that's the investments tab).
- No rebalancing maths, glidepaths, or constraints beyond non-negative weights.
- No server changes: reuses `estimatePortfolio` (μ/σ) and `runSimulation`.

## Data model

`households/{hid}/portfolios/{pid}` — mirrors `members` / `investments`.

| Field | Type | Notes |
|-------|------|-------|
| `name` | string | Required, e.g. "60/40 Growth". |
| `period` | string | History window for estimation (`1y`/`2y`/`5y`/`10y`/`max`); default `5y`. |
| `holdings` | array | `[{ ticker: string (upper-cased), weight: number }]`; blank-ticker rows dropped on write. |
| `createdAt` / `createdBy` | serverTimestamp / string | Set on create, never patched. |

Weights are stored **as entered** (e.g. 60/40) and normalized by
`estimate.portfolio_gbm_inputs` at simulation time, so the advisor can use
percentages or fractions interchangeably.

## Client design

- `SavedPortfolio` + `SavedPortfolioDraft` + `PortfolioHolding`
  (`lib/models/saved_portfolio.dart`). Named `Saved*` to avoid colliding with
  the existing `PortfolioService`/`PortfolioEstimate` (the estimation bridge).
- `SavedPortfolioService` — CRUD + name-sorted `watchPortfolios`, mirroring
  `InvestmentService`.
- Providers: `savedPortfolioServiceProvider`,
  `savedPortfoliosProvider.family(hid)`.
- **Portfolios tab** (replaces the "coming soon" stub): lists portfolios with a
  holding-count summary, a per-row **Simulate** action, tap-to-edit, delete; FAB
  to add.
- `SavedPortfolioFormScreen` — name + period dropdown + a dynamic list of
  ticker/weight rows (add/remove), with validation (name required, ≥1 ticker,
  positive weights) and a delete affordance, mirroring the other form screens.
- **Simulate** pushes `SimulationFormScreen(initialTickers, initialWeights,
  initialPeriod)`, reusing the existing estimate→GBM bridge (which fills μ/σ and
  shows the provenance banner). `SimulationFormScreen` gains an optional
  `initialPeriod` so the saved window is honored.

## Tests

- `test/saved_portfolio_test.dart` — model parsing, weight coercion, blank-row
  dropping, create payload.
- `test/saved_portfolio_service_test.dart` — CRUD + name-sorted watch +
  household scoping over `FakeFirebaseFirestore` (mirrors the member/investment
  service suites).
- `test/widgets/portfolios_tab_test.dart` — tab lists portfolios with summaries
  and Simulate buttons, empty state, and FAB → form navigation.

## Risks / open questions

- **Client-only, unrun here.** No Flutter toolchain in the authoring env; the
  Dart mirrors proven patterns and ships with tests, but must be exercised under
  `flutter test` in CI.
- **Weights vs. holdings semantics.** Saved weights are target allocations, not
  share counts; deliberately separate from the investments DB. A future nicety:
  "save current holdings as a portfolio" using value-weights.
