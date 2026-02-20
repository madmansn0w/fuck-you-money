"""Price fetching and cache management (CoinGecko API)."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Callable, Dict, Optional, Tuple

import requests

from crypto_tracker.config.constants import COINGECKO_API_URL

COINGECKO_ASSET_IDS = {
    "BTC": "bitcoin",
    "ETH": "ethereum",
    "BNB": "binancecoin",
    "ADA": "cardano",
    "SOL": "solana",
    "XRP": "ripple",
    "DOT": "polkadot",
    "DOGE": "dogecoin",
    "MATIC": "matic-network",
    "AVAX": "avalanche-2",
    "LINK": "chainlink",
    "UNI": "uniswap",
    "ATOM": "cosmos",
    "LTC": "litecoin",
    "ALGO": "algorand",
}


def fetch_price_and_24h(asset: str) -> Tuple[Optional[float], Optional[float]]:
    """
    Fetch current price and 24h % change from CoinGecko API.

    Returns:
        (price_usd, pct_change_24h). Either may be None. USDC returns (1.0, 0.0).
    """
    if (asset or "").upper() == "USDC":
        return (1.0, 0.0)
    coin_id = COINGECKO_ASSET_IDS.get((asset or "").upper(), (asset or "").lower())
    try:
        response = requests.get(
            COINGECKO_API_URL,
            params={"ids": coin_id, "vs_currencies": "usd", "include_24hr_change": "true"},
            timeout=5,
        )
        response.raise_for_status()
        data = response.json()
        if coin_id not in data or "usd" not in data[coin_id]:
            return (None, None)
        price = float(data[coin_id]["usd"])
        raw = data[coin_id].get("usd_24h_change") or data[coin_id].get(
            "price_change_percentage_24h_in_currency"
        )
        pct_24h = float(raw) if raw is not None else None
        return (price, pct_24h)
    except Exception:
        return (None, None)


def fetch_price_from_api(asset: str) -> Optional[float]:
    """Fetch current price only. Returns None on failure."""
    price, _ = fetch_price_and_24h(asset)
    return price


def get_current_price(
    asset: str,
    cache: Dict[str, Any],
    save_cache: Callable[[Dict[str, Any]], None],
    max_age_minutes: float = 5.0,
) -> Optional[float]:
    """
    Get current price from cache (if fresh) or API. Updates cache and calls save_cache when fetching.

    USDC always returns 1.0.
    """
    if (asset or "").upper() == "USDC":
        return 1.0
    if asset in cache:
        entry = cache[asset]
        try:
            ts = entry.get("timestamp")
            if ts:
                cache_time = datetime.strptime(ts, "%Y-%m-%d %H:%M:%S")
                age_min = (datetime.now() - cache_time).total_seconds() / 60
                if age_min < max_age_minutes:
                    return entry.get("price")
        except Exception:
            pass
    price, pct_24h = fetch_price_and_24h(asset)
    if price is not None:
        entry = {"price": price, "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
        if pct_24h is not None:
            entry["pct_change_24h"] = pct_24h
        cache[asset] = entry
        save_cache(cache)
        return price
    return None


def get_24h_pct(asset: str, cache: Dict[str, Any]) -> Optional[float]:
    """Return 24h % change from cache. USDC returns 0.0."""
    if (asset or "").upper() == "USDC":
        return 0.0
    if asset in cache and "pct_change_24h" in cache[asset]:
        return cache[asset]["pct_change_24h"]
    return None


def refresh_prices(
    assets: list[str],
    cache: Dict[str, Any],
    save_cache: Callable[[Dict[str, Any]], None],
) -> int:
    """
    Fetch and cache prices for all given assets (crypto only; USD/USDC skipped or treated as 1.0).
    Returns the number of assets successfully updated.
    """
    updated = 0
    for asset in assets:
        if (asset or "").upper() in ("USD", "USDC"):
            continue
        price, pct_24h = fetch_price_and_24h(asset)
        if price is not None:
            entry = {"price": price, "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
            if pct_24h is not None:
                entry["pct_change_24h"] = pct_24h
            cache[asset] = entry
            updated += 1
    if updated:
        save_cache(cache)
    return updated
