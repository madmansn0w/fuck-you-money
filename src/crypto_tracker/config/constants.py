"""Global configuration constants for Crypto Tracker.

These values are intentionally free of any UI / Tkinter concerns so they
can be reused by services, CLI tools, and the desktop application.
"""

from __future__ import annotations

from pathlib import Path

# Base directory for data files (defaults to project root)
BASE_DIR = Path(__file__).resolve().parents[3]

# --- File paths ---
USERS_FILE = str(BASE_DIR / "users.json")
DATA_FILE = str(BASE_DIR / "crypto_data.json")
PRICE_CACHE_FILE = str(BASE_DIR / "price_cache.json")

# API endpoints
COINGECKO_API_URL = "https://api.coingecko.com/api/v3/simple/price"

# Default exchange/wallet configuration with maker/taker fees (Bitstamp first for default)
DEFAULT_EXCHANGES = {
    "Bitstamp": {"maker": 0.30, "taker": 0.40},
    "Wallet": {"maker": 0.0, "taker": 0.0},
    "Binance": {"maker": 0.10, "taker": 0.10},
    "Coinbase Pro": {"maker": 0.40, "taker": 0.60},
    "Kraken": {"maker": 0.25, "taker": 0.40},
    "Bybit": {"maker": 0.10, "taker": 0.10},
    "Crypto.com": {"maker": 0.25, "taker": 0.50},
}

# Common cryptocurrency assets for dropdown (USD added for transactions)
COMMON_ASSETS = [
    "BTC",
    "ETH",
    "BNB",
    "ADA",
    "SOL",
    "XRP",
    "DOT",
    "DOGE",
    "MATIC",
    "AVAX",
    "LINK",
    "UNI",
    "ATOM",
    "LTC",
    "ALGO",
    "USDC",
]
TRANSACTION_ASSETS = ["USD"] + COMMON_ASSETS

# Transaction types: BUY/SELL for trading; Holding/Transfer = BTC (crypto) only;
# Withdrawal/Deposit = USD only
TRADE_TYPES_ALL = ["BUY", "SELL", "Holding", "Transfer", "Withdrawal", "Deposit"]
TRADE_TYPES_CRYPTO = ["BUY", "SELL", "Holding", "Transfer"]
TRADE_TYPES_USD = ["Deposit", "Withdrawal"]

# Types that are not part of "initial capital" for investment
# (Holding, Transfer, Withdrawal, Deposit)
NON_INVESTMENT_TYPES = {"Holding", "Transfer", "Withdrawal", "Deposit"}
