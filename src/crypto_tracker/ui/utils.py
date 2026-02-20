"""Shared UI utilities: colors for values, mousewheel binding."""

from __future__ import annotations

import tkinter as tk
from typing import Optional

from crypto_tracker.theming.style import (
    APPLE_COLOR_LOSS,
    APPLE_COLOR_PROFIT,
    SUMMARY_DESC_COLOR,
)


def color_for_value(value: Optional[float]) -> str:
    """
    Return foreground color for a numeric value (P&L, ROI, amount, etc.).
    Use only on the value widget, never on descriptors or whole rows.

    Args:
        value: Numeric value (e.g. P&L, ROI %, or amount).

    Returns:
        APPLE_COLOR_PROFIT if value > 0, APPLE_COLOR_LOSS if value < 0,
        SUMMARY_DESC_COLOR if value is None or exactly zero (neutral).
    """
    if value is None:
        return SUMMARY_DESC_COLOR
    try:
        v = float(value)
    except (TypeError, ValueError):
        return SUMMARY_DESC_COLOR
    if abs(v) < 1e-9:
        return SUMMARY_DESC_COLOR
    return APPLE_COLOR_PROFIT if v > 0 else APPLE_COLOR_LOSS


def bind_mousewheel_recursive(parent: tk.Widget, on_wheel) -> None:
    """
    Bind mouse wheel and scroll button events to parent and all descendants
    so touchpad/wheel scrolling works when the pointer is over any child (e.g. on macOS).
    on_wheel(event) should call yview_scroll or equivalent; it receives delta/num.
    """
    try:
        parent.bind("<MouseWheel>", on_wheel)
        parent.bind("<Button-4>", on_wheel)
        parent.bind("<Button-5>", on_wheel)
    except tk.TclError:
        pass
    for child in parent.winfo_children():
        bind_mousewheel_recursive(child, on_wheel)
