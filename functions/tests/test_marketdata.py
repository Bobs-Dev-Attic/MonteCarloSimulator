"""Tests for the yfinance DataFrame -> PriceHistory parsing.

These exercise :func:`montecarlo.marketdata._frame_to_history` with synthetic
pandas frames shaped like yfinance's output, so the parsing rules are verified
without any network access. (The live fetch itself can only be checked against
Yahoo Finance in a deployed/networked environment.)
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from montecarlo import marketdata


def _dates(n):
    return pd.date_range("2021-01-01", periods=n, freq="D")


def test_single_ticker_flat_frame():
    idx = _dates(4)
    # auto_adjust=True single-ticker frame: flat columns including "Close".
    raw = pd.DataFrame(
        {
            "Open": [10, 11, 12, 13],
            "High": [10, 11, 12, 13],
            "Low": [10, 11, 12, 13],
            "Close": [10.0, 11.0, 12.0, 13.0],
            "Volume": [100, 100, 100, 100],
        },
        index=idx,
    )
    hist = marketdata._frame_to_history(raw, ["AAPL"])
    assert hist.prices.shape == (4, 1)
    assert hist.prices[:, 0].tolist() == [10.0, 11.0, 12.0, 13.0]
    assert hist.dates[0] == "2021-01-01"


def test_multi_ticker_multiindex_frame():
    idx = _dates(3)
    cols = pd.MultiIndex.from_product(
        [["Close", "Open"], ["AAPL", "MSFT"]]
    )
    data = np.array([
        [10.0, 20.0, 9.9, 19.9],
        [11.0, 21.0, 10.9, 20.9],
        [12.0, 22.0, 11.9, 21.9],
    ])
    raw = pd.DataFrame(data, index=idx, columns=cols)
    hist = marketdata._frame_to_history(raw, ["AAPL", "MSFT"])
    assert hist.tickers == ["AAPL", "MSFT"]
    assert hist.prices.shape == (3, 2)
    assert hist.prices[0].tolist() == [10.0, 20.0]


def test_rows_with_gaps_are_dropped():
    idx = _dates(4)
    cols = pd.MultiIndex.from_product([["Close"], ["AAPL", "MSFT"]])
    data = np.array([
        [10.0, 20.0],
        [11.0, np.nan],  # MSFT missing -> whole row dropped
        [12.0, 22.0],
        [13.0, 23.0],
    ])
    raw = pd.DataFrame(data, index=idx, columns=cols)
    hist = marketdata._frame_to_history(raw, ["AAPL", "MSFT"])
    assert hist.prices.shape == (3, 2)


def test_empty_frame_raises():
    with pytest.raises(marketdata.MarketDataError):
        marketdata._frame_to_history(pd.DataFrame(), ["AAPL"])


def test_insufficient_history_raises():
    idx = _dates(1)
    raw = pd.DataFrame({"Close": [10.0]}, index=idx)
    with pytest.raises(marketdata.MarketDataError):
        marketdata._frame_to_history(raw, ["AAPL"])


def test_fetch_rejects_blank_tickers():
    with pytest.raises(marketdata.MarketDataError):
        marketdata.fetch_price_history(["", "  "])
