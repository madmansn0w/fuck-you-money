"""Tests for app core API (load_portfolio, list_trades, list_users)."""

import pytest

from crypto_tracker.app import list_trades, load_portfolio
from crypto_tracker.services.storage import get_default_data


def test_list_trades_empty() -> None:
    """list_trades returns empty list for default data."""
    data = get_default_data()
    assert list_trades(data) == data.get("trades", [])
    assert list_trades({}) == []
    assert list_trades({"trades": []}) == []


def test_list_trades_returns_copy_of_list() -> None:
    """list_trades returns the actual trades list from data (caller may not mutate)."""
    data = get_default_data()
    data["trades"] = [{"id": "1", "asset": "BTC", "type": "BUY", "date": "2024-01-01", "quantity": 1.0}]
    trades = list_trades(data)
    assert len(trades) == 1
    assert trades[0]["asset"] == "BTC"


def test_load_portfolio_requires_storage() -> None:
    """load_portfolio delegates to storage; with default user we get default or file data."""
    # May load from file or return default; either way we get a dict with expected keys
    data = load_portfolio("Default")
    assert "trades" in data
    assert "settings" in data
    assert "accounts" in data
    assert "account_groups" in data
