# Portfolio builder with yfinance-derived μ/σ

## Purpose

Today the **Portfolio (GBM)** model asks the advisor to type in an expected
annual return (μ) and a volatility (σ) by hand. That is the single biggest
source of garbage-in/garbage-out: most advisors don't have defensible numbers
in their head. This feature lets them instead **build a portfolio out of real
tickers** (e.g. 60% `VTI`, 40% `BND`), pull historical prices, and have the
server *derive* μ and σ — including the diversification benefit from the assets'
correlation — then drop those straight into the existing simulation.

This directly removes the README's standing limitation: *"live market-data
ingestion (μ/σ are user inputs)."*

## Feasibility determination (yfinance)

**Verdict: yes, yfinance can be leveraged for both current price and historical
analysis — as a server-side input-estimation source, wrapped with caching and a
manual fallback.** Findings from an in-environment spike:

- **Install:** `pip install yfinance` succeeds cleanly (pure Python; pulls
  `pandas`/`numpy`, already present). Verified `yfinance==1.4.1`.
- **API fit:** exactly matches our need —
  `yf.download(tickers, period, interval, auto_adjust=True)` returns aligned
  OHLCV history for one or many tickers; `Ticker.fast_info.last_price` gives a
  current quote. We only need adjusted **Close** columns.
- **Network:** the *sandbox* this was prototyped in uses an allowlist that
  blocks `query1/query2.finance.yahoo.com` (`403 Host not in allowlist`), so a
  live fetch can't be smoke-tested here. A deployed 2nd-gen Cloud Function has
  full outbound egress by default and will reach Yahoo; **if** the project later
  attaches VPC egress controls, Yahoo's hosts must be allowlisted.
- **Caveats (drive the design):** yfinance is an *unofficial* scraper of
  undocumented endpoints. No SLA; it rate-limits (HTTP 429), occasionally
  returns 401/403, and reshapes its JSON without notice. Therefore it must be
  (a) **isolated** behind one module, (b) **cached** so repeated runs of the
  same portfolio don't re-hit Yahoo, and (c) **degradable** — a fetch failure
  must never block a simulation; the user can always fall back to manual μ/σ.

## Non-goals

- Multi-asset *path* simulation (correlated GBM across assets). We collapse the
  basket into one synthetic (μ, σ) and reuse the existing single-asset GBM. The
  correlation matrix is computed and returned for display, not for sampling.
- Real-time / streaming quotes, intraday bars, options, fundamentals.
- Short positions or leverage (weights are non-negative, normalized to 1).
- Replacing manual entry. Manual μ/σ stays as the default and the fallback.
- Persisting a portfolio as its own first-class Firestore entity (a later step;
  see open questions).

## Methodology (server math)

Given a `(T, A)` matrix of adjusted closes (T daily observations, A assets):

1. **Log returns** `r_t = ln(P_t / P_{t-1})` — GBM is log-normal.
2. **Per asset:** annualize the sample mean and variance of log returns with
   `days = 252`. Report σ = `sqrt(var · 252)` and, in the simulator's drift
   convention where `E[S_T] = S_0·exp(μT)`, `μ = mean_log·252 + 0.5·σ²`.
3. **Portfolio collapse:** treat the basket as a synthetic asset whose per-step
   log return is `wᵀ·r` (exact under continuous rebalancing; first-order
   otherwise). Then with `Σ` = annualized covariance of log returns:
   - `σ_p = sqrt(wᵀ Σ w)` — captures diversification.
   - `μ_p = (w·mean_log)·252 + 0.5·σ_p²`.
4. **Correlation matrix** of log returns is returned for display.

This lives in `functions/montecarlo/estimate.py` as pure NumPy and is validated
by recovering known μ/σ from a long synthetic GBM series.

## Server design

### New module: `functions/montecarlo/estimate.py` (pure, no network)

```
log_returns(prices) -> (T-1, A) array
annualized_asset_stats(prices, trading_days=252) -> [ {mu, sigma, mean_log_return}, ... ]
correlation_matrix(prices) -> [[...]]
portfolio_gbm_inputs(prices, weights=None, trading_days=252)
    -> { mu, sigma, weights, assets: [...], correlation: [[...]], observations }
```

### New module: `functions/montecarlo/marketdata.py` (the only networked module)

```
class MarketDataError(RuntimeError): ...
@dataclass PriceHistory: tickers: list[str]; prices: np.ndarray; dates: list[str]
fetch_price_history(tickers, *, period="5y", interval="1d") -> PriceHistory
```

`yfinance` is imported **lazily** inside the fetch so the module imports (and is
unit-tested via a synthetic DataFrame against the private `_frame_to_history`
parser) without the dependency or network. Rows with any missing value are
dropped so all columns align on common trading days.

### `functions/main.py` — new callable `estimatePortfolio`

- Request: `{ tickers: [str], weights: [float]?, period: str?, interval: str? }`.
- Validates: 1–25 tickers; `period ∈ {1y,2y,5y,10y,max}`;
  `interval ∈ {1d,1wk,1mo}`.
- Calls `marketdata.fetch_price_history` then `estimate.portfolio_gbm_inputs`,
  and returns `mu`, `sigma`, `weights`, `assets`, `correlation`, `tickers`,
  `start_date`, `end_date`, `period`, `interval`.
- Error mapping: bad input → `INVALID_ARGUMENT`; `MarketDataError` →
  `UNAVAILABLE` (signals the client to fall back to manual entry).
- `runSimulation` is **unchanged**: the client takes the returned μ/σ and runs a
  normal `gbm` request, so estimation and simulation stay cleanly decoupled.

### Caching (recommended, server-side)

To shield Yahoo from repeat hits and absorb rate limits, cache each
`(sorted tickers, period, interval)` → estimation result in a Firestore
collection `marketDataCache/{hash}` with a TTL (e.g. 12h). On a cache miss or
fetch failure with a *stale* entry present, serve the stale entry and flag it.
This is in the plan but gated behind the live-fetch milestone.

## Client design

### Data model

- New `Portfolio` value type: `List<PortfolioHolding>` where a holding is
  `{ ticker: String, weight: double }`.
- `PortfolioEstimate` parses the callable response (`mu`, `sigma`, per-asset
  stats, correlation, date range).
- `SimulationConfig.gbm` is unchanged — it already takes `mu`/`sigma`; the form
  just fills them from the estimate.

### Service

- `PortfolioService.estimate(holdings, {period})` wraps the
  `estimatePortfolio` callable (mirrors `SimulationService.run`).

### Form (`simulation_form_screen.dart`)

- On the GBM tab, a new **"Build from tickers"** expansion panel above the μ/σ
  fields: add ticker rows (symbol + weight), a period dropdown, and an
  **Estimate from history** button.
- On success: μ and σ fields are populated (and visually marked "from history:
  AAPL, MSFT · 5y"), and a small read-only correlation/return summary appears.
- On `UNAVAILABLE`: a non-blocking SnackBar — "Couldn't fetch market data; enter
  μ/σ manually" — leaving the manual fields fully usable.

### Results provenance

When a simulation was seeded from an estimate, persist the source portfolio
(tickers + weights + window) alongside the saved sim so history shows *why* the
μ/σ were what they were, and a saved tile shows a small "from tickers" chip.

## Risks and open questions

- **yfinance reliability in prod.** Mitigated by isolation + cache + manual
  fallback. If Yahoo proves too flaky, `marketdata.py` is the single seam to
  swap for a sanctioned provider (Alpha Vantage, Tiingo, Polygon) behind the
  same `PriceHistory` contract.
- **Egress policy.** Confirm the deployed function's network policy allows
  `*.finance.yahoo.com` before relying on it.
- **Synthetic-asset approximation.** Collapsing to one (μ, σ) ignores
  rebalancing drag and assumes the portfolio is continuously rebalanced to the
  target weights. Acceptable for a planning tool and documented in `estimate.py`.
- **Survivorship / look-ahead.** Estimating μ from a trailing window is
  backward-looking by construction; the UI should label it as "historical,"
  not "expected," and keep the field editable.
- **Portfolio persistence.** This spec stops at "estimate → fill the form." A
  follow-up can promote `Portfolio` to a saved entity (likely under a household,
  reusing the advisor/household model) and let an advisor re-estimate on demand.
