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


# ----------------------------- quotes ----------------------------------------

def test_quotes_multi_ticker_takes_latest_close():
    idx = _dates(3)
    cols = pd.MultiIndex.from_product([["Close"], ["AAPL", "MSFT"]])
    data = np.array([
        [10.0, 20.0],
        [11.0, 21.0],
        [12.0, 22.0],
    ])
    raw = pd.DataFrame(data, index=idx, columns=cols)
    out = marketdata._frame_to_quotes(raw, ["AAPL", "MSFT"])
    assert out["quotes"]["AAPL"]["price"] == 12.0
    assert out["quotes"]["MSFT"]["price"] == 22.0
    assert out["quotes"]["AAPL"]["as_of"] == "2021-01-03"
    assert out["missing"] == []


def test_quotes_resolve_per_ticker_independently():
    # MSFT's latest day is missing; it should fall back to its own prior close,
    # NOT be dropped just because AAPL has a value that day.
    idx = _dates(3)
    cols = pd.MultiIndex.from_product([["Close"], ["AAPL", "MSFT"]])
    data = np.array([
        [10.0, 20.0],
        [11.0, 21.0],
        [12.0, np.nan],
    ])
    raw = pd.DataFrame(data, index=idx, columns=cols)
    out = marketdata._frame_to_quotes(raw, ["AAPL", "MSFT"])
    assert out["quotes"]["AAPL"]["price"] == 12.0
    assert out["quotes"]["MSFT"]["price"] == 21.0  # last valid MSFT close
    assert out["missing"] == []


def test_quotes_single_ticker_flat_frame():
    idx = _dates(2)
    raw = pd.DataFrame({"Close": [10.0, 11.5]}, index=idx)
    out = marketdata._frame_to_quotes(raw, ["AAPL"])
    assert out["quotes"]["AAPL"]["price"] == 11.5


def test_quotes_unknown_ticker_listed_missing():
    idx = _dates(2)
    cols = pd.MultiIndex.from_product([["Close"], ["AAPL", "ZZZZ"]])
    data = np.array([[10.0, np.nan], [11.0, np.nan]])
    raw = pd.DataFrame(data, index=idx, columns=cols)
    out = marketdata._frame_to_quotes(raw, ["AAPL", "ZZZZ"])
    assert "AAPL" in out["quotes"]
    assert out["missing"] == ["ZZZZ"]


def test_quotes_all_missing_raises():
    idx = _dates(2)
    cols = pd.MultiIndex.from_product([["Close"], ["ZZZZ"]])
    raw = pd.DataFrame(np.array([[np.nan], [np.nan]]), index=idx, columns=cols)
    with pytest.raises(marketdata.MarketDataError):
        marketdata._frame_to_quotes(raw, ["ZZZZ"])
