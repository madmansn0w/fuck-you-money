"""Tests for UI utility functions (no GUI deps)."""

import pytest

from crypto_tracker.theming.style import APPLE_COLOR_LOSS, APPLE_COLOR_PROFIT, SUMMARY_DESC_COLOR
from crypto_tracker.ui.utils import color_for_value


def test_color_for_value_positive() -> None:
    """Positive values use profit (green) color."""
    assert color_for_value(1.0) == APPLE_COLOR_PROFIT
    assert color_for_value(0.01) == APPLE_COLOR_PROFIT


def test_color_for_value_negative() -> None:
    """Negative values use loss (red) color."""
    assert color_for_value(-1.0) == APPLE_COLOR_LOSS
    assert color_for_value(-0.01) == APPLE_COLOR_LOSS


def test_color_for_value_zero_or_none() -> None:
    """Zero and None use neutral descriptor color."""
    assert color_for_value(0.0) == SUMMARY_DESC_COLOR
    assert color_for_value(None) == SUMMARY_DESC_COLOR
    assert color_for_value(1e-12) == SUMMARY_DESC_COLOR


def test_color_for_value_invalid() -> None:
    """Non-numeric values fall back to neutral."""
    assert color_for_value("x") == SUMMARY_DESC_COLOR  # type: ignore[arg-type]
