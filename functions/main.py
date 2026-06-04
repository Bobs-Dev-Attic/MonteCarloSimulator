"""Firebase Cloud Functions (2nd gen, Python) entry point.

Exposes a single authenticated HTTPS Callable, ``runSimulation``, that the
Flutter app invokes via the ``cloud_functions`` package. The heavy NumPy
sampling happens here, server-side; only compact aggregated results are
returned (and then persisted to Firestore by the client).
"""

from __future__ import annotations

import firebase_admin
from firebase_functions import https_fn, options

from montecarlo import aggregate, estimate, marketdata
from montecarlo.gbm import simulate_gbm
from montecarlo.garch import simulate_gbm_garch
from montecarlo.retirement import simulate_retirement, success_rate

firebase_admin.initialize_app()

# Bound compute/cost: never run more than this many paths per request.
MAX_SIMS = 50_000
DEFAULT_SIMS = 10_000

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


def _run_retirement(inputs: dict, n_sims: int, seed: int | None) -> dict:
    starting = float(inputs["starting_balance"])
    history = simulate_retirement(
        starting_balance=starting,
        annual_contribution=float(inputs.get("annual_contribution", 0.0)),
        years_to_retire=int(inputs["years_to_retire"]),
        retirement_years=int(inputs["retirement_years"]),
        annual_withdrawal=float(inputs["annual_withdrawal"]),
        mean_return=float(inputs["mean_return"]),
        std_return=float(inputs["std_return"]),
        inflation=float(inputs.get("inflation", 0.0)),
        n_sims=n_sims,
        seed=seed,
    )
    terminal = history[-1]
    summary = aggregate.summary_stats(terminal, starting, success_threshold=0.0)
    # For retirement, "success" means not running out of money.
    summary["success_rate"] = success_rate(history)
    return {
        "bands": aggregate.percentile_bands(history),
        "histogram": aggregate.terminal_histogram(terminal),
        "summary": summary,
    }


_MODELS = {"gbm": _run_gbm, "retirement": _run_retirement}

# Bound the history window an advisor can request so a single call stays cheap.
ALLOWED_PERIODS = {"1y", "2y", "5y", "10y", "max"}
ALLOWED_INTERVALS = {"1d", "1wk", "1mo"}
MAX_TICKERS = 25


def _estimate_portfolio(inputs: dict) -> dict:
    """Derive GBM ``mu``/``sigma`` from a basket of tickers' price history.

    Fetches historical closes via :mod:`montecarlo.marketdata`, then collapses
    the basket into a single drift/volatility pair (plus per-asset stats and the
    correlation matrix) via :mod:`montecarlo.estimate`. The returned ``mu`` and
    ``sigma`` are ready to drop straight into a ``gbm`` simulation request.
    """
    tickers = inputs.get("tickers") or []
    if not isinstance(tickers, list) or not tickers:
        raise ValueError("provide a non-empty 'tickers' list")
    if len(tickers) > MAX_TICKERS:
        raise ValueError(f"at most {MAX_TICKERS} tickers per request")

    weights = inputs.get("weights")
    period = str(inputs.get("period", "5y"))
    interval = str(inputs.get("interval", "1d"))
    if period not in ALLOWED_PERIODS:
        raise ValueError(f"period must be one of {sorted(ALLOWED_PERIODS)}")
    if interval not in ALLOWED_INTERVALS:
        raise ValueError(f"interval must be one of {sorted(ALLOWED_INTERVALS)}")

    history = marketdata.fetch_price_history(
        [str(t) for t in tickers], period=period, interval=interval
    )
    stats = estimate.portfolio_gbm_inputs(history.prices, weights=weights)
    stats["tickers"] = history.tickers
    stats["period"] = period
    stats["interval"] = interval
    stats["start_date"] = history.dates[0]
    stats["end_date"] = history.dates[-1]
    return stats


@https_fn.on_call(
    memory=options.MemoryOption.MB_512,
    timeout_sec=60,
)
def estimatePortfolio(req: https_fn.CallableRequest) -> dict:
    """Estimate GBM inputs for a portfolio of tickers from historical prices.

    Request data: ``{ "tickers": [str], "weights": [float]?, "period": str?,
    "interval": str? }``. Returns ``mu``/``sigma`` plus per-asset stats, the
    correlation matrix, and the resolved date range. Market data comes from
    Yahoo Finance via yfinance; failures surface as ``UNAVAILABLE`` so the
    client can fall back to manual ``mu``/``sigma`` entry.
    """
    if req.auth is None:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            "You must be signed in to estimate a portfolio.",
        )

    inputs = req.data or {}
    try:
        return _estimate_portfolio(inputs)
    except ValueError as exc:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT, str(exc)
        )
    except marketdata.MarketDataError as exc:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.UNAVAILABLE,
            f"Could not fetch market data: {exc}",
        )


@https_fn.on_call(
    memory=options.MemoryOption.MB_512,
    timeout_sec=120,
)
def runSimulation(req: https_fn.CallableRequest) -> dict:
    """Run a Monte Carlo simulation and return aggregated results.

    Request data: ``{ "model": "gbm"|"retirement", "inputs": {...},
    "n_sims": int?, "seed": int?, "compare_garch": bool? }``.
    GBM only: when ``compare_garch`` is true, a ``"comparison"`` key is
    added to the result containing a GARCH(1,1) run with the same inputs.
    """
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
