"""Historical market-data fetch via yfinance.

This is the *only* module in the package that touches the network, and it does
so through `yfinance <https://pypi.org/project/yfinance/>`_ — an unofficial
client for Yahoo Finance's undocumented endpoints. It is deliberately thin: pull
adjusted closing prices for a set of tickers, hand back a plain NumPy matrix
plus metadata, and let :mod:`montecarlo.estimate` do the deterministic math.

Why isolate it
--------------
yfinance is convenient and free but has no SLA: Yahoo rate-limits, occasionally
returns 401/403/429, and reshapes its JSON without notice. Keeping every network
concern here means the simulation math stays pure and unit-testable, and the
callable layer can catch :class:`MarketDataError` and fall back to manual
``mu``/``sigma`` inputs without the rest of the system knowing yfinance exists.

``yfinance`` is imported lazily inside the fetch function so importing this
module (e.g. during unit tests that monkeypatch the fetch) never requires the
dependency or network access.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


class MarketDataError(RuntimeError):
    """Raised when historical prices cannot be retrieved or are unusable."""


@dataclass(frozen=True)
class PriceHistory:
    """Aligned historical closes for one or more tickers.

    Attributes:
        tickers: Symbols, in the same column order as ``prices``.
        prices: ``(T, A)`` matrix of adjusted closing prices, oldest first,
            with rows containing any missing value already dropped so every
            column is aligned on common trading days.
        dates: ISO-8601 date strings (length ``T``), oldest first.
    """

    tickers: list[str]
    prices: np.ndarray
    dates: list[str]


def fetch_price_history(
    tickers: list[str],
    *,
    period: str = "5y",
    interval: str = "1d",
) -> PriceHistory:
    """Fetch adjusted closing prices for ``tickers`` from Yahoo Finance.

    Args:
        tickers: One or more ticker symbols (e.g. ``["AAPL", "MSFT"]``).
        period: yfinance period string (``"1y"``, ``"5y"``, ``"max"``, ...).
        interval: yfinance bar interval (``"1d"``, ``"1wk"``, ``"1mo"``).

    Returns:
        A :class:`PriceHistory` with a clean, aligned price matrix.

    Raises:
        MarketDataError: on bad input, network/parse failure, or empty result.
    """
    symbols = [t.strip().upper() for t in tickers if t and t.strip()]
    if not symbols:
        raise MarketDataError("no tickers provided")

    try:
        import yfinance as yf  # lazy: keeps import-time deps minimal
    except ImportError as exc:  # pragma: no cover - environment-dependent
        raise MarketDataError(
            "yfinance is not installed; cannot fetch market data"
        ) from exc

    try:
        raw = yf.download(
            symbols,
            period=period,
            interval=interval,
            auto_adjust=True,
            progress=False,
            group_by="column",
        )
    except Exception as exc:  # yfinance raises a grab-bag of error types
        raise MarketDataError(f"market-data request failed: {exc}") from exc

    return _frame_to_history(raw, symbols)


def _frame_to_history(raw, symbols: list[str]) -> PriceHistory:
    """Convert a yfinance DataFrame into an aligned :class:`PriceHistory`.

    Split out from the network call so it can be unit-tested with a synthetic
    DataFrame and so the parsing rules live in one place.
    """
    if raw is None or getattr(raw, "empty", True):
        raise MarketDataError(
            "no price data returned (check ticker symbols and period)"
        )

    # With auto_adjust=True the adjusted price lives in the "Close" column. For a
    # single ticker the frame is flat; for many it's a column MultiIndex.
    close = raw["Close"] if "Close" in raw.columns else raw
    close = close.to_frame() if hasattr(close, "to_frame") and close.ndim == 1 else close

    # Keep requested symbols that actually came back, preserving caller order.
    available = [s for s in symbols if s in close.columns]
    if not available:
        # Single-ticker frames may have a generic column name; fall back to all.
        available = list(close.columns)
    close = close[available]

    # Drop any row with a gap so all columns share the same trading days.
    close = close.dropna(how="any")
    if close.shape[0] < 2:
        raise MarketDataError(
            "insufficient overlapping history for the requested tickers"
        )

    prices = np.asarray(close.to_numpy(), dtype=float)
    dates = [str(d)[:10] for d in close.index]
    resolved = [str(c) for c in close.columns]
    return PriceHistory(tickers=resolved, prices=prices, dates=dates)
