# Per-customer investments database (live-priced via yfinance)

## Purpose

Give each customer (a `household`) a persistent **investments database**: the
real securities they hold. An advisor can add holdings by ticker and quantity;
the app prices them **live** via Yahoo Finance (yfinance) to show current market
value and a portfolio total, and can hand the basket to the GBM simulator with
data-derived μ/σ. This turns the simulator from "type in two numbers" into
"model the portfolio this customer actually owns."

## Decisions (from the requester)

- **Records are minimal: ticker + quantity.** No cost basis, account type, or
  notes in v1. The model uses a `Draft` so those are cheap to add later.
- **Live pricing via yfinance**, and the basket **feeds the simulator** — the
  Investments tab's "Simulate" action seeds the GBM form with the holdings'
  tickers and value-weights, which calls the existing `estimatePortfolio` to set
  μ/σ.

## Non-goals

- Cost basis / unrealized gain-loss, lots, account types, transactions.
- Real-time/streaming quotes (we use the latest daily close).
- Editing holdings from the simulator; the database is the source of truth.
- Server-side persistence of quotes (they're fetched on demand; caching is a
  later optimization shared with the portfolio-estimation feature).

## Data model

Firestore: `households/{hid}/investments/{iid}` — mirrors `members`.

| Field | Type | Notes |
|-------|------|-------|
| `ticker` | string | Upper-cased, trimmed on write. |
| `quantity` | number | Shares (fractional allowed). |
| `createdAt` | serverTimestamp | Set on create, never patched. |
| `createdBy` | string | Advisor uid. |

Security rule mirrors `members`/`portfolios`: read/write iff the caller's uid is
in the parent household's `advisorIds`.

`Investment.marketValue(price)` = `price == null ? null : price * quantity`.
Value is always derived, never stored.

## Server design

### `fetchQuotes` callable (new) + `marketdata.fetch_quotes`

- Request: `{ tickers: [str] }` (≤ 100). Response:
  `{ quotes: { TICKER: { price: float, as_of: "YYYY-MM-DD" } }, missing: [str] }`.
- Auth-gated. `ValueError → INVALID_ARGUMENT`, `MarketDataError → UNAVAILABLE`.
- `marketdata.fetch_quotes` downloads a short window and resolves each ticker's
  latest **non-missing** close *independently* — a gap in one symbol must not
  blank the others (contrast `fetch_price_history`, which aligns on common days
  for return analysis). Symbols with no usable price go in `missing` rather than
  raising, so one bad ticker never sinks the basket. Parser
  (`_frame_to_quotes`) is unit-tested with synthetic frames.

`runSimulation` and `estimatePortfolio` are unchanged.

## Client design

### Models / services

- `Investment` + `InvestmentDraft` (ticker, quantity) — mirror `Member`.
- `InvestmentService` — CRUD + `watchInvestments` (sorted by ticker), mirror
  `MemberService`.
- `QuoteService.fetchQuotes(tickers) -> QuotesResult { quotes, missing }`.
- `PortfolioService.estimate(...) -> PortfolioEstimate { mu, sigma, tickers,
  weights, dates }` — wraps `estimatePortfolio` (the simulate bridge).

### Providers

- `investmentServiceProvider`, `investmentsProvider.family(hid)`.
- `quoteServiceProvider`, `quotesProvider.family(tickersCsv)` — the family key is
  the unique, upper-cased, **sorted** ticker list joined by commas, so identical
  baskets share one request and it re-runs only when the ticker *set* changes.
- `portfolioServiceProvider`.

### Screens

- **HouseholdDetailScreen** gains a third tab: **Members | Investments |
  Portfolios**. The Investments tab:
  - Streams holdings; watches `quotesProvider` for live prices.
  - Header card: total market value (spinner while loading), a "No price for: …"
    note when `missing` is non-empty, and a **Simulate** button.
  - Each row: ticker avatar, `@ $price · N sh`, market value, edit/delete.
  - **Simulate** computes value-weights over the priced holdings and pushes
    `SimulationFormScreen(initialTickers, initialWeights)`.
- **InvestmentFormScreen** — create/edit/delete; ticker `TextFormField`
  (auto-upper-cased, symbol-charset filtered) + quantity `ScrubField`. Mirrors
  `MemberFormScreen` including the delete affordance and error surfacing.
- **SimulationFormScreen** — new optional `initialTickers`/`initialWeights`. On
  init it calls `PortfolioService.estimate`, fills μ/σ (fraction→percent), and
  shows a provenance banner ("From history: AAPL, MSFT · 2021-…→2026-…"). On
  failure: a non-blocking SnackBar; manual entry stays usable. Existing
  parameterless usage is unaffected.

## Risks and open questions

- **yfinance reliability** — same caveats as the estimation feature; quotes
  degrade gracefully (`missing` list, manual μ/σ fallback). A later shared cache
  (`marketDataCache/{hash}`, short TTL) would cut repeat hits.
- **Value-weighting needs prices** — if all quotes fail, Simulate falls back to
  equal weights so the bridge still works.
- **No cost basis** means no gain/loss yet; the schema is forward-compatible
  (additive fields on `InvestmentDraft`).
- **Client tests** for the new widgets/services mirror the member suite but
  could not be executed in this environment (no Flutter toolchain); they must be
  run in CI / locally (`flutter test`).
