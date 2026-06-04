# MonteCarloSimulator

A cross-platform **Flutter** app, backed by **Firebase**, that runs **Monte Carlo
simulations** for financial analysis. Instead of relying on a single static average
return, it runs thousands of randomized scenarios to map the full *spectrum* of
possible outcomes and the probabilities attached to them.

Two models are included:

- **Portfolio / asset forecast (GBM)** — Geometric Brownian Motion using a drift
  (expected return) and volatility (standard deviation).
- **Retirement accumulation + withdrawal** — year-by-year saving then drawdown,
  reporting the probability of *not running out of money*.

## Architecture

```
 Flutter app  ──(HTTPS Callable: runSimulation)──►  Python Cloud Function (NumPy)
   │  Firebase Auth (sign in)                          │ vectorized GBM / retirement sampling
   │  Input form                                       │ aggregates → percentile bands + histogram
   │                                                   ▼
   └──────────── Firestore (per-user) ◄── writes config + aggregated result ──┘
        users/{uid}/simulations/{simId}
   Flutter listens to Firestore → fan chart + terminal histogram + summary stats
```

The heavy NumPy sampling runs **server-side** in a 2nd-gen Python Cloud Function.
Only compact *aggregated* results (percentile bands, a histogram, and summary
stats) are returned to the device — never the 10,000 raw paths — and then saved
to Firestore so history reloads instantly.

## Layout

| Path | Purpose |
|------|---------|
| `lib/` | Flutter app (models, services, state, screens, chart widgets) |
| `functions/` | Python Cloud Functions: `main.py` callable + `montecarlo/` math |
| `functions/montecarlo/` | `gbm.py`, `retirement.py`, `aggregate.py` (pure NumPy) |
| `functions/tests/` | pytest unit tests for the simulation math |
| `scripts/prototype.py` | Standalone NumPy + matplotlib prototype for validation |
| `firestore.rules` | Per-user access control |

## The methodology

1. **Deterministic baseline**: `EndingValue = BeginningValue × (1 + Return)`.
2. **Uncertain variable**: `Return` is modeled as a normal distribution defined by
   an expected mean (drift, μ) and volatility (std dev, σ).
3. **Iterate**: generate ~10,000 random paths over the horizon (vectorized NumPy).
4. **Analyze the distribution**: percentiles, probability of loss / success, VaR.

GBM step: `S_{t+1} = S_t · exp((μ − ½σ²)·dt + σ·√dt·Z)`, with `Z ~ N(0, 1)`.

## Getting started

### 1. Validate the math (no Firebase needed)

```bash
pip install numpy matplotlib pytest
cd functions && pytest            # unit tests for the models
cd ../scripts && python prototype.py   # prints stats + saves plots to scripts/out/
```

### 2. Configure Firebase

```bash
# Create a Firebase project, then:
dart pub global activate flutterfire_cli
flutterfire configure             # regenerates lib/firebase_options.dart
# Set your project id in .firebaserc, enable Auth (Email + Google) and Firestore.
```

> `lib/firebase_options.dart`, `google-services.json`, and `GoogleService-Info.plist`
> are placeholders/ignored — `flutterfire configure` generates real ones for you.

### 3. Run locally against the emulator suite

```bash
firebase emulators:start          # Auth + Firestore + Functions
flutter pub get
flutter run --dart-define=USE_EMULATOR=true
```

### 4. Deploy

```bash
firebase deploy --only functions,firestore:rules
```

## Tests

- **Python**: `cd functions && pytest` — shape, reproducibility (seed), GBM mean vs.
  analytic expectation, retirement success-rate bounds, aggregation ordering.
- **Flutter**: `flutter test` — config payloads and result parsing.

## Portfolio estimation from market data

The GBM model's μ (drift) and σ (volatility) can be **derived from historical
prices** instead of typed in by hand. The `estimatePortfolio` Cloud Function
takes a basket of tickers (and optional weights), fetches adjusted closes via
[yfinance](https://pypi.org/project/yfinance/), and returns annualized μ/σ plus
per-asset stats and the correlation matrix — capturing the diversification
benefit through the full covariance. Those μ/σ feed a normal `runSimulation`
call, so estimation and simulation stay decoupled.

- `functions/montecarlo/estimate.py` — pure NumPy: prices → GBM inputs.
- `functions/montecarlo/marketdata.py` — the only networked module (yfinance,
  lazily imported); failures surface as `UNAVAILABLE` so the client falls back
  to manual μ/σ entry.

yfinance is an unofficial Yahoo Finance client with no SLA, so it is isolated
behind one module and meant to be paired with caching + manual fallback. See
`docs/superpowers/specs/2026-06-04-portfolio-yfinance-design.md`.

## Out of scope (for now)

Correlated multi-asset *path* simulation, fat-tailed/jump models, real-time
quotes, and CI/CD.
