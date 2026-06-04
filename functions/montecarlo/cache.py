"""A tiny TTL cache for market-data results, with stale-on-failure.

yfinance is unsanctioned and rate-limited, so we don't want to hit Yahoo on
every request, and a transient failure shouldn't break a screen that worked a
minute ago. :func:`cached_fetch` wraps any fetch with three behaviors:

* **fresh hit** — return the stored value if it's within the TTL;
* **miss / expired** — call ``fetch``, store, and return the fresh value;
* **fetch failure with a prior value** — return the *stale* value (flagged)
  instead of raising, so the client degrades gracefully.

The storage backend is injected (a ``get(key)``/``set(key, entry)`` pair) so the
orchestration is pure and unit-testable; :class:`FirestoreStore` is the
production backend and :class:`InMemoryStore` is for tests/cold-start.
"""

from __future__ import annotations

import hashlib
import json
import time

from .marketdata import MarketDataError


def make_key(kind: str, **params) -> str:
    """Stable cache key from a kind tag and JSON-serializable params.

    Params are serialized with sorted keys so equivalent requests (regardless of
    dict ordering) map to the same key. Lists should be pre-sorted by the caller
    when order is not semantically meaningful (e.g. a set of tickers).
    """
    blob = json.dumps({"kind": kind, "params": params}, sort_keys=True,
                      separators=(",", ":"))
    digest = hashlib.sha256(blob.encode("utf-8")).hexdigest()[:32]
    return f"{kind}_{digest}"


class InMemoryStore:
    """Process-local cache backend. Survives only the warm instance."""

    def __init__(self) -> None:
        self._data: dict[str, dict] = {}

    def get(self, key: str) -> dict | None:
        return self._data.get(key)

    def set(self, key: str, entry: dict) -> None:
        self._data[key] = entry


class FirestoreStore:
    """Cache backend over a Firestore collection of ``{value, stored_at}`` docs."""

    def __init__(self, collection) -> None:
        self._col = collection

    def get(self, key: str) -> dict | None:
        snap = self._col.document(key).get()
        return snap.to_dict() if snap.exists else None

    def set(self, key: str, entry: dict) -> None:
        self._col.document(key).set(entry)


def cached_fetch(store, key, ttl_seconds, fetch, *, now=None) -> dict:
    """Return a cached value or fetch a fresh one, with stale-on-failure.

    Args:
        store: backend exposing ``get(key)`` and ``set(key, entry)``.
        key: cache key (see :func:`make_key`).
        ttl_seconds: freshness window.
        fetch: zero-arg callable returning a dict result to cache.
        now: injectable clock (epoch seconds) for testing.

    Returns:
        The result dict. A served-from-cache result gains ``"cached": True``;
        a value served after a failed refresh also gains ``"stale": True``.

    Raises:
        Whatever ``fetch`` raises when there is no prior value to fall back to.
        Non-:class:`MarketDataError` exceptions always propagate (e.g. a
        ``ValueError`` for bad input must surface, not serve stale).
    """
    now = time.time() if now is None else now
    entry = store.get(key)
    if entry is not None and (now - entry.get("stored_at", 0)) < ttl_seconds:
        return {**entry["value"], "cached": True}

    try:
        value = fetch()
    except MarketDataError:
        if entry is not None:
            return {**entry["value"], "cached": True, "stale": True}
        raise

    store.set(key, {"value": value, "stored_at": now})
    return value
