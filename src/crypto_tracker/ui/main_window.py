"""Main application window for Crypto Tracker.

Re-exports the legacy CryptoTrackerApp until the UI is fully split into
summary, transactions, and dialogs modules.
"""

from crypto_tracker.legacy_crypto_tracker import CryptoTrackerApp

__all__ = ["CryptoTrackerApp"]
