"""UI package for Crypto Tracker: main window, summary, transactions, and dialogs."""

__all__ = ["CryptoTrackerApp"]


def __getattr__(name: str):
    """Lazy-load CryptoTrackerApp so ui.utils/dialogs can be used without GUI deps."""
    if name == "CryptoTrackerApp":
        from crypto_tracker.ui.main_window import CryptoTrackerApp
        return CryptoTrackerApp
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
