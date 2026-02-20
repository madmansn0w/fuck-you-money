"""Tests for portfolio metrics (cost basis and aggregate metrics)."""

import pytest

from crypto_tracker.services.metrics import (
    calculate_cost_basis_average,
    calculate_cost_basis_fifo,
    calculate_cost_basis_lifo,
    compute_portfolio_metrics,
)


def test_compute_portfolio_metrics_empty() -> None:
    """Empty trades return zeroed metrics."""
    def _no_price(asset: str):
        return None
    out = compute_portfolio_metrics([], "average", _no_price)
    assert out["per_asset"] == {}
    assert out["total_value"] == 0.0
    assert out["total_external_cash"] == 0.0
    assert out["realized_pnl"] == 0.0
    assert out["unrealized_pnl"] == 0.0
    assert out["total_pnl"] == 0.0
    assert out["roi_pct"] == 0.0
    assert "roi_on_cost_pct" in out


def test_cost_basis_fifo_single_buy() -> None:
    """FIFO: one BUY gives cost basis and units held."""
    trades = [
        {"asset": "BTC", "type": "BUY", "date": "2024-01-01", "quantity": 1.0, "total_value": 40000.0, "fee": 40.0},
    ]
    cost, units, lots = calculate_cost_basis_fifo(trades, "BTC")
    assert cost == pytest.approx(40040.0)
    assert units == pytest.approx(1.0)
    assert len(lots) == 1


def test_cost_basis_average_single_buy() -> None:
    """Average: one BUY matches FIFO."""
    trades = [
        {"asset": "BTC", "type": "BUY", "date": "2024-01-01", "quantity": 1.0, "total_value": 40000.0, "fee": 40.0},
    ]
    cost, units, _ = calculate_cost_basis_average(trades, "BTC")
    assert cost == pytest.approx(40040.0)
    assert units == pytest.approx(1.0)


def test_cost_basis_lifo_single_buy() -> None:
    """LIFO: one BUY matches FIFO."""
    trades = [
        {"asset": "BTC", "type": "BUY", "date": "2024-01-01", "quantity": 1.0, "total_value": 40000.0, "fee": 40.0},
    ]
    cost, units, _ = calculate_cost_basis_lifo(trades, "BTC")
    assert cost == pytest.approx(40040.0)
    assert units == pytest.approx(1.0)
