"""Portfolio and per-asset metrics computation (pure functions)."""

from __future__ import annotations

from typing import Any, Callable, Dict, List, Optional, Tuple

from crypto_tracker.models.core import PortfolioMetrics


def calculate_cost_basis_fifo(
    trades: List[Dict[str, Any]], asset: str
) -> Tuple[float, float, List[Dict[str, Any]]]:
    """
    Calculate cost basis using FIFO (First In First Out) method.

    Returns:
        Tuple of (total_cost_basis, units_held, remaining_lots).
    """
    asset_trades = [t for t in trades if t.get("asset") == asset]
    asset_trades.sort(key=lambda x: x.get("date", ""))

    lots: List[Dict[str, Any]] = []
    total_cost = 0.0
    units_held = 0.0

    for trade in asset_trades:
        if trade.get("type") in ("BUY", "Transfer"):
            qty = trade.get("quantity") or 0
            total_val = (trade.get("total_value") or 0) + (trade.get("fee") or 0)
            cost_per_unit = total_val / qty if qty else 0
            if cost_per_unit > 0 and qty > 0:
                lots.append({
                    "quantity": qty,
                    "cost_per_unit": cost_per_unit,
                    "trade_id": trade.get("id"),
                    "date": trade.get("date", ""),
                })
                units_held += qty
                total_cost += total_val
        elif trade.get("type") == "SELL":
            sell_qty = trade.get("quantity") or 0
            units_held -= sell_qty
            while sell_qty > 0 and lots:
                lot = lots[0]
                q = lot["quantity"]
                if q <= sell_qty:
                    total_cost -= q * lot["cost_per_unit"]
                    sell_qty -= q
                    lots.pop(0)
                else:
                    total_cost -= sell_qty * lot["cost_per_unit"]
                    lot["quantity"] -= sell_qty
                    sell_qty = 0
    return total_cost, units_held, lots


def calculate_cost_basis_lifo(
    trades: List[Dict[str, Any]], asset: str
) -> Tuple[float, float, List[Dict[str, Any]]]:
    """
    Calculate cost basis using LIFO (Last In First Out) method.

    Returns:
        Tuple of (total_cost_basis, units_held, remaining_lots).
    """
    asset_trades = [t for t in trades if t.get("asset") == asset]
    asset_trades.sort(key=lambda x: x.get("date", ""))

    lots: List[Dict[str, Any]] = []
    total_cost = 0.0
    units_held = 0.0

    for trade in asset_trades:
        if trade.get("type") in ("BUY", "Transfer"):
            qty = trade.get("quantity") or 0
            total_val = (trade.get("total_value") or 0) + (trade.get("fee") or 0)
            cost_per_unit = total_val / qty if qty else 0
            if cost_per_unit > 0 and qty > 0:
                lots.append({
                    "quantity": qty,
                    "cost_per_unit": cost_per_unit,
                    "trade_id": trade.get("id"),
                    "date": trade.get("date", ""),
                })
                units_held += qty
                total_cost += total_val
        elif trade.get("type") == "SELL":
            sell_qty = trade.get("quantity") or 0
            units_held -= sell_qty
            while sell_qty > 0 and lots:
                lot = lots[-1]
                q = lot["quantity"]
                if q <= sell_qty:
                    total_cost -= q * lot["cost_per_unit"]
                    sell_qty -= q
                    lots.pop()
                else:
                    total_cost -= sell_qty * lot["cost_per_unit"]
                    lot["quantity"] -= sell_qty
                    sell_qty = 0
    return total_cost, units_held, lots


def calculate_cost_basis_average(
    trades: List[Dict[str, Any]], asset: str
) -> Tuple[float, float, List[Dict[str, Any]]]:
    """
    Calculate cost basis using Average Cost method.

    Returns:
        Tuple of (total_cost_basis, units_held, remaining_lots).
    """
    asset_trades = [t for t in trades if t.get("asset") == asset]
    asset_trades.sort(key=lambda x: x.get("date", ""))

    total_cost = 0.0
    units_held = 0.0

    for trade in asset_trades:
        if trade.get("type") in ("BUY", "Transfer"):
            qty = trade.get("quantity") or 0
            units_held += qty
            total_cost += (trade.get("total_value") or 0) + (trade.get("fee") or 0)
        elif trade.get("type") == "SELL":
            sell_qty = trade.get("quantity") or 0
            units_held -= sell_qty
            if units_held > 0:
                avg = total_cost / (units_held + sell_qty)
                total_cost = units_held * avg
            else:
                total_cost = 0.0

    lots: List[Dict[str, Any]] = []
    if units_held > 0:
        avg_cost = total_cost / units_held
        lots.append({
            "quantity": units_held,
            "cost_per_unit": avg_cost,
            "trade_id": "average",
            "date": "average",
        })
    return total_cost, units_held, lots


def compute_portfolio_metrics(
    trades: List[Dict[str, Any]],
    cost_basis_method: str,
    get_current_price: Callable[[str], Optional[float]],
) -> PortfolioMetrics:
    """
    Compute portfolio metrics from a list of trades.

    Single source of truth for per-asset positions, cost basis, USD cash,
    total value, realized/unrealized P&L, and ROI. Requires a price provider
    (e.g. cache + API) via get_current_price(asset) -> price or None.
    """
    if not trades:
        return {
            "per_asset": {},
            "usd_balance": 0.0,
            "total_value": 0.0,
            "total_external_cash": 0.0,
            "total_cost_basis_assets": 0.0,
            "realized_pnl": 0.0,
            "unrealized_pnl": 0.0,
            "total_pnl": 0.0,
            "roi_pct": 0.0,
            "roi_on_cost_pct": None,
        }

    trades_sorted = sorted(trades, key=lambda t: t.get("date", ""))

    usd_deposits = sum(
        t.get("quantity", 0) for t in trades_sorted
        if t.get("asset") == "USD" and t.get("type") == "Deposit"
    )
    usd_withdrawals = sum(
        t.get("quantity", 0) for t in trades_sorted
        if t.get("asset") == "USD" and t.get("type") == "Withdrawal"
    )
    total_external_cash = usd_deposits - usd_withdrawals

    crypto_assets = sorted({t["asset"] for t in trades_sorted if t.get("asset") != "USD"})
    per_asset: Dict[str, Dict[str, Any]] = {}
    total_cost_basis_assets = 0.0
    total_unrealized_pnl = 0.0
    total_value_assets = 0.0

    method = cost_basis_method if cost_basis_method in ("fifo", "lifo", "average") else "average"
    for asset in crypto_assets:
        asset_trades = [t for t in trades_sorted if t.get("asset") == asset]
        if not asset_trades:
            continue

        if method == "fifo":
            cost_basis, units_held, _ = calculate_cost_basis_fifo(asset_trades, asset)
        elif method == "lifo":
            cost_basis, units_held, _ = calculate_cost_basis_lifo(asset_trades, asset)
        else:
            cost_basis, units_held, _ = calculate_cost_basis_average(asset_trades, asset)

        buy_cost_asset = sum(
            (t.get("total_value") or 0) + (t.get("fee") or 0)
            for t in asset_trades
            if t.get("type") in ("BUY", "Transfer")
        )
        sell_proceeds_asset = sum(
            (t.get("total_value") or 0) - (t.get("fee") or 0)
            for t in asset_trades
            if t.get("type") == "SELL"
        )
        realized_pnl_asset = sell_proceeds_asset - (buy_cost_asset - cost_basis)

        holding_qty = sum(t.get("quantity", 0) for t in asset_trades if t.get("type") == "Holding")
        total_units_for_value = units_held + holding_qty

        price = get_current_price(asset)
        if price is None or price <= 0:
            current_value = cost_basis
        else:
            current_value = total_units_for_value * price

        unrealized = current_value - cost_basis
        roi_pct_asset = (unrealized / cost_basis * 100.0) if cost_basis > 0 else 0.0
        lifetime_pnl_asset = realized_pnl_asset + unrealized

        per_asset[asset] = {
            "units_held": units_held,
            "holding_qty": holding_qty,
            "price": price,
            "current_value": current_value,
            "cost_basis": cost_basis,
            "unrealized_pnl": unrealized,
            "realized_pnl": realized_pnl_asset,
            "lifetime_pnl": lifetime_pnl_asset,
            "roi_pct": roi_pct_asset,
        }
        total_cost_basis_assets += cost_basis
        total_unrealized_pnl += unrealized
        total_value_assets += current_value

    usd_balance = total_external_cash
    for t in trades_sorted:
        if t.get("asset") == "USD" or t.get("type") not in ("BUY", "SELL"):
            continue
        total_val = float(t.get("total_value") or (t.get("price") or 0) * (t.get("quantity") or 0))
        fee = float(t.get("fee") or 0)
        if t.get("type") == "BUY":
            usd_balance -= (total_val + fee)
        else:
            usd_balance += (total_val - fee)

    total_value = total_value_assets + usd_balance
    total_buy_cost = sum(
        (t.get("total_value") or 0) + (t.get("fee") or 0)
        for t in trades_sorted
        if t.get("type") in ("BUY", "Transfer") and t.get("asset") != "USD"
    )
    total_sell_proceeds = sum(
        (t.get("total_value") or 0) - (t.get("fee") or 0)
        for t in trades_sorted
        if t.get("type") == "SELL" and t.get("asset") != "USD"
    )
    realized_pnl = total_sell_proceeds - (total_buy_cost - total_cost_basis_assets)
    total_pnl = realized_pnl + total_unrealized_pnl
    roi_pct = (total_pnl / total_external_cash * 100.0) if total_external_cash > 0 else 0.0
    roi_on_cost_pct = (total_pnl / total_cost_basis_assets * 100.0) if total_cost_basis_assets > 0 else None

    return {
        "per_asset": per_asset,
        "usd_balance": usd_balance,
        "total_value": total_value,
        "total_external_cash": total_external_cash,
        "total_cost_basis_assets": total_cost_basis_assets,
        "realized_pnl": realized_pnl,
        "unrealized_pnl": total_unrealized_pnl,
        "total_pnl": total_pnl,
        "roi_pct": roi_pct,
        "roi_on_cost_pct": roi_on_cost_pct,
    }
