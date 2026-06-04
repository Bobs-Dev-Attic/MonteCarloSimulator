# Per-customer investments database — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A per-household investments database (ticker + quantity) priced live
via yfinance, with a portfolio total and a one-tap bridge to simulate the basket
through the existing GBM model.

**Architecture:** A `fetchQuotes` Cloud Function prices tickers (latest close,
resolved per-ticker). The client mirrors the household/member CRUD pattern for
`Investment`, adds `QuoteService` (live prices) and `PortfolioService` (the
`estimatePortfolio` simulate bridge), and surfaces an Investments tab on
`HouseholdDetailScreen`. `SimulationFormScreen` gains optional seed
tickers/weights that auto-derive μ/σ.

**Tech Stack:** Python 3.11 + NumPy + pandas + yfinance + firebase-functions;
Flutter + Riverpod + cloud_functions + cloud_firestore; pytest; flutter_test.

---

## Task 1: `fetchQuotes` server callable  ✅ DONE (verified)

- [x] `marketdata.fetch_quotes` + `_frame_to_quotes` (per-ticker latest close,
  `missing` list, raises only when *nothing* resolves).
- [x] `main._fetch_quotes` runner + `fetchQuotes` callable (≤100 tickers; error
  mapping to INVALID_ARGUMENT / UNAVAILABLE).
- [x] Tests: 6 quote-parser cases + 3 runner cases, all mocked/synthetic.
  Full functions suite **52 passed**.
- [x] Committed.

## Task 2: Investment model + service  ✅ DONE (written; tests pending CI)

- [x] `lib/models/investment.dart` (`Investment`, `InvestmentDraft`,
  `marketValue`), `lib/services/investment_service.dart` (CRUD + watch sorted
  by ticker).
- [x] `test/investment_test.dart`, `test/investment_service_test.dart` mirror
  the member suites.
- [ ] **Run `flutter test test/investment_*.dart`** — requires a Flutter
  toolchain (absent in the authoring sandbox). Must pass in CI/local.

## Task 3: Quote + Portfolio services and providers  ✅ DONE (written)

- [x] `lib/services/quote_service.dart` (`Quote`, `QuotesResult`,
  `fetchQuotes`), `lib/services/portfolio_service.dart` (`PortfolioEstimate`,
  `estimate`).
- [x] Providers: `investmentServiceProvider`, `investmentsProvider.family`,
  `quoteServiceProvider`, `quotesProvider.family`, `portfolioServiceProvider`.
- [x] `QuoteService.parse` extracted as a pure static method; covered by
  `test/quote_service_test.dart` (quotes/missing/stale + `PortfolioEstimate`).
  Run in CI.

## Task 4: Investment form + Investments tab  ✅ DONE (written)

- [x] `lib/screens/investment_form_screen.dart` (ticker + quantity; upper-case
  formatter; delete affordance) mirroring `MemberFormScreen`.
- [x] `HouseholdDetailScreen` → 3 tabs; Investments tab with live total,
  `missing` note, per-row market value, and the **Simulate** button computing
  value-weights.
- [x] **Widget test** `test/widgets/investments_tab_test.dart`: real
  `InvestmentService` over `FakeFirebaseFirestore` + mocked `QuoteService`.
  Asserts live per-row values, the portfolio total, the "no price"/"stale"
  notes, the empty state, and FAB → form navigation. Run in CI.

## Task 5: Simulate bridge on the GBM form  ✅ DONE (written)

- [x] `SimulationFormScreen` optional `initialTickers`/`initialWeights`; on init
  calls `PortfolioService.estimate`, fills μ/σ, shows provenance banner, and
  degrades to a SnackBar + manual entry on failure. Existing callers unaffected.

## Task 6: Firestore rules  ✅ DONE

- [x] `investments/{iid}` sub-collection rule mirrors `members`/`portfolios`
  (advisor-of-household gate).
- [ ] **Verify** with the rules emulator before deploy.

---

## Task 7: Deploy + smoke-test  ⬜ TODO

- [ ] `cd functions && pytest -v` → all pass (currently 52).
- [ ] `flutter test` → all pass (run the new Dart suites here).
- [ ] `firebase deploy --only functions,firestore:rules` (adds `fetchQuotes`).
- [ ] Manual: open a household → **Investments** → add `AAPL` 10, `MSFT` 5 →
  confirm live values + total → **Simulate** → GBM form shows the "From history"
  banner with μ/σ populated → **Run**. Then add a bogus ticker and confirm it
  appears under "No price for:" without breaking the total.

---

## Status

- **Server (Task 1): done and verified** here (52 passing).
- **Client (Tasks 2–6): written**, mirroring the proven member CRUD pattern, but
  **not compiled/tested** in the authoring sandbox (no Flutter). The Dart test
  suites are included and must be run in CI/local, and the live yfinance fetch is
  only exercisable post-deploy.
