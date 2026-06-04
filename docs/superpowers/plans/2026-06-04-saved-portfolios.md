# Saved (model) portfolios — Implementation Plan

**Goal:** Turn the stub Portfolios tab into named, reusable baskets of tickers +
weights per household, each re-simulatable on demand via the existing
estimate→GBM bridge. No server changes.

**Tech Stack:** Flutter + Riverpod + cloud_firestore; flutter_test +
fake_cloud_firestore.

---

## Task 1: Model  ✅ DONE (written; tests pending CI)

- [x] `lib/models/saved_portfolio.dart`: `PortfolioHolding`,
  `SavedPortfolioDraft` (drops blank-ticker rows, upper-cases), `SavedPortfolio`
  (`fromDoc`, `toCreatePayload`, `tickers`/`weights` getters).
- [x] `test/saved_portfolio_test.dart`.

## Task 2: Service + providers  ✅ DONE

- [x] `lib/services/saved_portfolio_service.dart` — CRUD + name-sorted
  `watchPortfolios`.
- [x] `savedPortfolioServiceProvider`, `savedPortfoliosProvider.family`.
- [x] `test/saved_portfolio_service_test.dart`.

## Task 3: Form screen  ✅ DONE

- [x] `lib/screens/saved_portfolio_form_screen.dart` — name, period dropdown,
  dynamic ticker/weight rows (add/remove), validation, delete.

## Task 4: Portfolios tab + Simulate bridge  ✅ DONE

- [x] `household_detail_screen.dart`: real `_PortfoliosTab` (list, summaries,
  Simulate, edit, delete, FAB).
- [x] `SimulationFormScreen` gains optional `initialPeriod`; Simulate passes the
  saved tickers/weights/period.
- [x] `test/widgets/portfolios_tab_test.dart`.

## Task 5: Firestore rule  ✅ DONE (pre-existing)

- [x] `households/{hid}/portfolios/{pid}` rule already present (advisor-of-
  household gate) — no change needed.

---

## Task 6: Verify + ship  ⬜ TODO

- [ ] `flutter test` (the 3 new suites + existing) — **must run in CI**; no
  Flutter toolchain in the authoring env.
- [ ] `flutter analyze` clean.
- [ ] Manual: household → **Portfolios** → add "60/40 Growth" (VTI 60 / BND 40,
  5y) → Simulate → GBM form shows provenance banner with μ/σ → Run. Edit, then
  delete.

## Status

Client feature **written and unit-tested by construction**, mirroring the
member/investment patterns; no server changes. CI (`flutter test`) is the first
real compile/run.
