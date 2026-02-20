"""Application bootstrap and core API entrypoints for Crypto Tracker.

Provides a small core API (load_portfolio, list_trades, list_users) for use
by the desktop UI, future CLI, or scripts. The GUI is still launched via
the legacy Tkinter module until the UI is fully modularized.
"""

from __future__ import annotations

from typing import Any, Dict, List

from .services import storage


def load_portfolio(username: str = "Default") -> Dict[str, Any]:
    """Load portfolio data for a user (trades, accounts, settings).

    Uses the same paths and migrations as the GUI. Raises on I/O error.

    Args:
        username: User name; data is loaded from crypto_data_{username}.json.

    Returns:
        Data dict with keys: trades, accounts, account_groups, settings.
    """
    return storage.load_data(username)


def list_trades(data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Return the flat list of trades from loaded portfolio data.

    Args:
        data: Result of load_portfolio().

    Returns:
        List of trade dicts (date, asset, type, quantity, price, fee, etc.).
    """
    return data.get("trades", [])


def list_users() -> List[str]:
    """Return the list of configured usernames (no file path needed)."""
    return storage.load_users()


def main() -> None:
    """Launch the Crypto Tracker Tkinter application.

    This thin wrapper keeps backwards compatibility while the codebase
    is being modularized into a proper package.
    """
    from . import legacy_crypto_tracker  # Deferred so core API is usable without GUI deps

    legacy_crypto_tracker.main()
