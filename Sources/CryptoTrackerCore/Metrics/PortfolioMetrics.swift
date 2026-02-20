import Foundation

/// Per-asset metrics; matches Python compute_portfolio_metrics per_asset value.
public struct PerAssetMetrics {
    public var units_held: Double
    public var holding_qty: Double
    public var price: Double?
    public var current_value: Double
    public var cost_basis: Double
    public var unrealized_pnl: Double
    public var realized_pnl: Double
    public var lifetime_pnl: Double
    public var roi_pct: Double
}

/// Aggregate portfolio metrics; matches Python return shape.
public struct PortfolioMetrics {
    public var per_asset: [String: PerAssetMetrics]
    public var usd_balance: Double
    public var total_value: Double
    public var total_external_cash: Double
    public var total_cost_basis_assets: Double
    public var realized_pnl: Double
    public var unrealized_pnl: Double
    public var total_pnl: Double
    public var roi_pct: Double
    public var roi_on_cost_pct: Double?
}

/// Trading performance analytics: drawdown, risk-adjusted returns, win rate.
public struct TradingAnalytics {
    /// Maximum peak-to-trough decline in portfolio value (USD).
    public var max_drawdown: Double
    /// Maximum drawdown as percentage of peak value (0–100).
    public var max_drawdown_pct: Double
    /// Sharpe ratio (mean return / std return); risk-free rate assumed 0.
    public var sharpe_ratio: Double?
    /// Sortino ratio (mean return / downside deviation).
    public var sortino_ratio: Double?
    /// Percentage of trades with profit > 0 (among trades with defined P&L).
    public var win_rate_pct: Double?
    /// Total number of trades (BUY + SELL, or all if preferred).
    public var total_trades: Int
    /// Number of profitable trades.
    public var winning_trades: Int
    /// Number of losing trades.
    public var losing_trades: Int
    /// Realized volatility: standard deviation of period returns from equity curve (e.g. daily). Optional.
    public var realized_volatility: Double?
}

/// Pairwise correlation of return series for analytics (e.g. correlation matrix / heatmap).
/// - `assets`: Ordered list of asset symbols (e.g. ["BTC", "ETH", "SOL"]).
/// - `matrix`: Symmetric N×N matrix; `matrix[i][j]` is Pearson correlation of returns for `assets[i]` and `assets[j]` (1.0 on diagonal).
public struct CorrelationMatrix {
    public var assets: [String]
    public var matrix: [[Double]]
}
