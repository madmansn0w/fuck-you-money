"""Centralized theming and typography for the Crypto Tracker UI."""

from __future__ import annotations

import tkinter as tk
import ttkbootstrap as tb

# Apple Design Constants
APPLE_FONT_FAMILY = "SF Pro Display"  # Primary font, falls back to system default
APPLE_FONT_DEFAULT = ("SF Pro Display", 12)  # Use tuple so Tk doesn't parse family as "SF", size "Pro"
APPLE_COLOR_PROFIT = "#30D158"  # Green
APPLE_COLOR_LOSS = "#FF3B30"    # Red
APPLE_SPACING_SMALL = 4
APPLE_SPACING_MEDIUM = 8
APPLE_SPACING_LARGE = 16
APPLE_SPACING_XLARGE = 24
APPLE_PADDING = 16
APPLE_BORDER_RADIUS = 8

# Max widths for sidebar/summary so they don't exceed content (with padding)
MAX_SIDEBAR_WIDTH = 220
MAX_SUMMARY_WIDTH = 400

# Tighter spacing in summary panel so content fits narrower column
SUMMARY_PAD = 4
SUMMARY_OUTER_PAD = 18
SUMMARY_CONTENT_PADX = 12
SUMMARY_SECTIONS_WIDTH = int(360)
SUMMARY_VALUE_FONT = ("SF Pro Display", 14, "bold")
SUMMARY_DESC_FONT = ("SF Pro Display", 9)
SUMMARY_DESC_COLOR = "#888888"  # Gray for descriptor labels (summary, entry/exit, etc.)


def setup_styles(root: tk.Misc) -> tb.Style:
    """Configure ttk/ttkbootstrap styles for a consistent macOS-inspired look.

    ttkbootstrap.Style is a singleton and does not take master; root is kept
    for API compatibility with callers.
    """
    style = tb.Style()
    # Apple-style thin scrollbars + rounded button appearance
    style.configure("Vertical.TScrollbar", gripcount=0, width=8, arrowsize=0)
    style.configure("Horizontal.TScrollbar", gripcount=0, width=8, arrowsize=0)
    style.map("Vertical.TScrollbar", background=[("active", "#404040")])
    style.map("Horizontal.TScrollbar", background=[("active", "#404040")])
    try:
        style.configure("TButton", padding=(14, 8))
        style.configure("primary.TButton", padding=(14, 8))
        style.configure("success.TButton", padding=(14, 8))
        style.configure("danger.TButton", padding=(14, 8))
        style.configure("Pct.TButton", padding=(8, 4))  # 25/50/75/100% buttons
        # Per-asset table: one font size smaller
        style.configure("Asset.Treeview", font=(APPLE_FONT_FAMILY, 11))
    except tk.TclError:
        # Some environments may not support style reconfiguration; fail gracefully.
        pass
    return style
