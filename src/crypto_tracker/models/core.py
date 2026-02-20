"""Typed structures for portfolio and asset metrics (for documentation and API)."""

from __future__ import annotations

from typing import Any, TypedDict


class PerAssetMetrics(TypedDict, total=False):
    """Per-asset metrics as returned by compute_portfolio_metrics."""

    units_held: float
    holding_qty: float
    price: float | None
    current_value: float
    cost_basis: float
    unrealized_pnl: float
    realized_pnl: float
    lifetime_pnl: float
    roi_pct: float


class PortfolioMetrics(TypedDict, total=False):
    """Aggregate portfolio metrics as returned by compute_portfolio_metrics."""

    per_asset: dict[str, dict[str, Any]]
    usd_balance: float
    total_value: float
    total_external_cash: float
    total_cost_basis_assets: float
    realized_pnl: float
    unrealized_pnl: float
    total_pnl: float
    roi_pct: float
    roi_on_cost_pct: float | None
