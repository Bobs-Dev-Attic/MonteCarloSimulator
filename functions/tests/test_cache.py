"""Tests for the TTL market-data cache with stale-on-failure."""

from __future__ import annotations

import pytest

from montecarlo import cache
from montecarlo.marketdata import MarketDataError


def test_make_key_is_order_independent():
    a = cache.make_key("quotes", tickers=["AAPL", "MSFT"], period="5d")
    b = cache.make_key("quotes", period="5d", tickers=["AAPL", "MSFT"])
    assert a == b
    assert a.startswith("quotes_")


def test_make_key_differs_on_params():
    a = cache.make_key("quotes", tickers=["AAPL"])
    b = cache.make_key("quotes", tickers=["MSFT"])
    c = cache.make_key("estimate", tickers=["AAPL"])
    assert a != b != c and a != c


def test_fresh_hit_skips_fetch():
    store = cache.InMemoryStore()
    calls = {"n": 0}

    def fetch():
        calls["n"] += 1
        return {"price": 100.0}

    first = cache.cached_fetch(store, "k", ttl_seconds=60, fetch=fetch, now=1000)
    assert first == {"price": 100.0}
    assert calls["n"] == 1

    second = cache.cached_fetch(store, "k", ttl_seconds=60, fetch=fetch, now=1030)
    assert second == {"price": 100.0, "cached": True}
    assert calls["n"] == 1  # fetch not called again


def test_expired_entry_refetches():
    store = cache.InMemoryStore()
    calls = {"n": 0}

    def fetch():
        calls["n"] += 1
        return {"v": calls["n"]}

    cache.cached_fetch(store, "k", ttl_seconds=60, fetch=fetch, now=1000)
    # Past the TTL -> refetch.
    out = cache.cached_fetch(store, "k", ttl_seconds=60, fetch=fetch, now=1100)
    assert out == {"v": 2}
    assert calls["n"] == 2


def test_failure_serves_stale_when_available():
    store = cache.InMemoryStore()

    good = cache.cached_fetch(
        store, "k", ttl_seconds=60, fetch=lambda: {"price": 50.0}, now=1000
    )
    assert good == {"price": 50.0}

    def failing():
        raise MarketDataError("yahoo 429")

    # Entry is now expired AND the refetch fails -> serve stale, flagged.
    out = cache.cached_fetch(store, "k", ttl_seconds=60, fetch=failing, now=2000)
    assert out == {"price": 50.0, "cached": True, "stale": True}


def test_failure_without_prior_value_raises():
    store = cache.InMemoryStore()

    def failing():
        raise MarketDataError("nope")

    with pytest.raises(MarketDataError):
        cache.cached_fetch(store, "k", ttl_seconds=60, fetch=failing, now=1000)


def test_non_marketdata_errors_propagate_even_with_stale():
    store = cache.InMemoryStore()
    cache.cached_fetch(
        store, "k", ttl_seconds=60, fetch=lambda: {"ok": True}, now=1000
    )

    def bad_input():
        raise ValueError("bad tickers")

    # A ValueError must surface (becomes INVALID_ARGUMENT), not serve stale.
    with pytest.raises(ValueError):
        cache.cached_fetch(store, "k", ttl_seconds=60, fetch=bad_input, now=2000)


def test_stale_flag_absent_on_fresh_fetch():
    store = cache.InMemoryStore()
    out = cache.cached_fetch(
        store, "k", ttl_seconds=60, fetch=lambda: {"x": 1}, now=1000
    )
    assert "cached" not in out and "stale" not in out
