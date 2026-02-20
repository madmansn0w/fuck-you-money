import Foundation

/// Cost basis and portfolio metrics; port of Python metrics_service.
public struct MetricsService {
    public init() {}

    /// FIFO cost basis. Returns (cost_basis, units_held, remaining_lots).
    public func calculateCostBasisFifo(trades: [Trade], asset: String) -> (costBasis: Double, unitsHeld: Double, lots: [[String: Any]]) {
        let assetTrades = trades.filter { $0.asset == asset }.sorted { $0.date < $1.date }
        var lots: [(qty: Double, costPerUnit: Double)] = []
        var totalCost = 0.0
        var unitsHeld = 0.0

        for t in assetTrades {
            if t.type == "BUY" || t.type == "Transfer" {
                let qty = t.quantity
                let totalVal = t.total_value + t.fee
                let costPerUnit = qty > 0 ? totalVal / qty : 0
                if costPerUnit > 0, qty > 0 {
                    lots.append((qty, costPerUnit))
                    unitsHeld += qty
                    totalCost += totalVal
                }
            } else if t.type == "SELL" {
                var sellQty = t.quantity
                unitsHeld -= sellQty
                while sellQty > 0, !lots.isEmpty {
                    var lot = lots[0]
                    if lot.qty <= sellQty {
                        totalCost -= lot.qty * lot.costPerUnit
                        sellQty -= lot.qty
                        lots.removeFirst()
                    } else {
                        totalCost -= sellQty * lot.costPerUnit
                        lot.qty -= sellQty
                        lots[0] = lot
                        sellQty = 0
                    }
                }
            }
        }
        let lotsDict = lots.map { ["quantity": $0.qty, "cost_per_unit": $0.costPerUnit] as [String: Any] }
        return (totalCost, unitsHeld, lotsDict)
    }

    /// LIFO cost basis.
    public func calculateCostBasisLifo(trades: [Trade], asset: String) -> (costBasis: Double, unitsHeld: Double, lots: [[String: Any]]) {
        let assetTrades = trades.filter { $0.asset == asset }.sorted { $0.date < $1.date }
        var lots: [(qty: Double, costPerUnit: Double)] = []
        var totalCost = 0.0
        var unitsHeld = 0.0

        for t in assetTrades {
            if t.type == "BUY" || t.type == "Transfer" {
                let qty = t.quantity
                let totalVal = t.total_value + t.fee
                let costPerUnit = qty > 0 ? totalVal / qty : 0
                if costPerUnit > 0, qty > 0 {
                    lots.append((qty, costPerUnit))
                    unitsHeld += qty
                    totalCost += totalVal
                }
            } else if t.type == "SELL" {
                var sellQty = t.quantity
                unitsHeld -= sellQty
                while sellQty > 0, !lots.isEmpty {
                    let idx = lots.count - 1
                    var lot = lots[idx]
                    if lot.qty <= sellQty {
                        totalCost -= lot.qty * lot.costPerUnit
                        sellQty -= lot.qty
                        lots.removeLast()
                    } else {
                        totalCost -= sellQty * lot.costPerUnit
                        lot.qty -= sellQty
                        lots[idx] = lot
                        sellQty = 0
                    }
                }
            }
        }
        let lotsDict = lots.map { ["quantity": $0.qty, "cost_per_unit": $0.costPerUnit] as [String: Any] }
        return (totalCost, unitsHeld, lotsDict)
    }

    /// Average cost basis.
    public func calculateCostBasisAverage(trades: [Trade], asset: String) -> (costBasis: Double, unitsHeld: Double, lots: [[String: Any]]) {
        let assetTrades = trades.filter { $0.asset == asset }.sorted { $0.date < $1.date }
        var totalCost = 0.0
        var unitsHeld = 0.0

        for t in assetTrades {
            if t.type == "BUY" || t.type == "Transfer" {
                unitsHeld += t.quantity
                totalCost += t.total_value + t.fee
            } else if t.type == "SELL" {
                let sellQty = t.quantity
                unitsHeld -= sellQty
                if unitsHeld > 0 {
                    let avg = totalCost / (unitsHeld + sellQty)
                    totalCost = unitsHeld * avg
                } else {
                    totalCost = 0
                }
            }
        }
        var lots: [[String: Any]] = []
        if unitsHeld > 0 {
            lots = [["quantity": unitsHeld, "cost_per_unit": totalCost / unitsHeld]]
        }
        return (totalCost, unitsHeld, lots)
    }

    /// Compute full portfolio metrics; getCurrentPrice(asset) -> price or nil.
    public func computePortfolioMetrics(
        trades: [Trade],
        costBasisMethod: String,
        getCurrentPrice: (String) -> Double?
    ) -> PortfolioMetrics {
        if trades.isEmpty {
            return PortfolioMetrics(
                per_asset: [:],
                usd_balance: 0,
                total_value: 0,
                total_external_cash: 0,
                total_cost_basis_assets: 0,
                realized_pnl: 0,
                unrealized_pnl: 0,
                total_pnl: 0,
                roi_pct: 0,
                roi_on_cost_pct: nil
            )
        }

        let sortedTrades = trades.sorted { $0.date < $1.date }
        let usdDeposits = sortedTrades.filter { $0.asset == "USD" && $0.type == "Deposit" }.reduce(0.0) { $0 + $1.quantity }
        let usdWithdrawals = sortedTrades.filter { $0.asset == "USD" && $0.type == "Withdrawal" }.reduce(0.0) { $0 + $1.quantity }
        let totalExternalCash = usdDeposits - usdWithdrawals

        let cryptoAssets = Set(sortedTrades.map(\.asset)).filter { $0 != "USD" }.sorted()
        var perAsset: [String: PerAssetMetrics] = [:]
        var totalCostBasisAssets = 0.0
        var totalUnrealizedPnl = 0.0
        var totalValueAssets = 0.0

        let method = (costBasisMethod == "fifo" || costBasisMethod == "lifo" || costBasisMethod == "average") ? costBasisMethod : "average"

        for asset in cryptoAssets {
            let assetTrades = sortedTrades.filter { $0.asset == asset }
            let (costBasis, unitsHeld, _): (Double, Double, [[String: Any]])
            switch method {
            case "fifo": (costBasis, unitsHeld, _) = calculateCostBasisFifo(trades: assetTrades, asset: asset)
            case "lifo": (costBasis, unitsHeld, _) = calculateCostBasisLifo(trades: assetTrades, asset: asset)
            default: (costBasis, unitsHeld, _) = calculateCostBasisAverage(trades: assetTrades, asset: asset)
            }

            let buyCostAsset = assetTrades.filter { $0.type == "BUY" || $0.type == "Transfer" }.reduce(0.0) { $0 + $1.total_value + $1.fee }
            let sellProceedsAsset = assetTrades.filter { $0.type == "SELL" }.reduce(0.0) { $0 + $1.total_value - $1.fee }
            let realizedPnlAsset = sellProceedsAsset - (buyCostAsset - costBasis)

            let holdingQty = assetTrades.filter { $0.type == "Holding" }.reduce(0.0) { $0 + $1.quantity }
            let totalUnitsForValue = unitsHeld + holdingQty

            var price = getCurrentPrice(asset)
            // When price cache has no price (e.g. before refresh), use most recent BUY/SELL price so ROI can be shown.
            if price == nil || price == 0, totalUnitsForValue > 0 {
                let lastTradeWithPrice = assetTrades
                    .filter { ($0.type == "BUY" || $0.type == "SELL") && $0.quantity > 0 }
                    .sorted { $0.date > $1.date }
                    .first
                if let t = lastTradeWithPrice {
                    let impliedPrice = t.total_value > 0 ? t.total_value / t.quantity : t.price
                    if impliedPrice > 0 { price = impliedPrice }
                }
            }
            let currentValue = (price ?? 0) > 0 ? totalUnitsForValue * (price ?? 0) : costBasis
            let unrealized = currentValue - costBasis
            let roiPctAsset = costBasis > 0 ? (unrealized / costBasis * 100) : 0
            let lifetimePnlAsset = realizedPnlAsset + unrealized

            perAsset[asset] = PerAssetMetrics(
                units_held: unitsHeld,
                holding_qty: holdingQty,
                price: price,
                current_value: currentValue,
                cost_basis: costBasis,
                unrealized_pnl: unrealized,
                realized_pnl: realizedPnlAsset,
                lifetime_pnl: lifetimePnlAsset,
                roi_pct: roiPctAsset
            )
            totalCostBasisAssets += costBasis
            totalUnrealizedPnl += unrealized
            totalValueAssets += currentValue
        }

        var usdBalance = totalExternalCash
        for t in sortedTrades {
            if t.asset == "USD" || (t.type != "BUY" && t.type != "SELL") { continue }
            let totalVal = t.total_value
            let fee = t.fee
            if t.type == "BUY" { usdBalance -= (totalVal + fee) }
            else { usdBalance += (totalVal - fee) }
        }

        let totalValue = totalValueAssets + usdBalance
        let totalBuyCost = sortedTrades.filter { ($0.type == "BUY" || $0.type == "Transfer") && $0.asset != "USD" }.reduce(0.0) { $0 + $1.total_value + $1.fee }
        let totalSellProceeds = sortedTrades.filter { $0.type == "SELL" && $0.asset != "USD" }.reduce(0.0) { $0 + $1.total_value - $1.fee }
        let realizedPnl = totalSellProceeds - (totalBuyCost - totalCostBasisAssets)
        let totalPnl = realizedPnl + totalUnrealizedPnl
        let roiPct = totalExternalCash > 0 ? (totalPnl / totalExternalCash * 100) : 0
        let roiOnCostPct = totalCostBasisAssets > 0 ? (totalPnl / totalCostBasisAssets * 100) : nil

        return PortfolioMetrics(
            per_asset: perAsset,
            usd_balance: usdBalance,
            total_value: totalValue,
            total_external_cash: totalExternalCash,
            total_cost_basis_assets: totalCostBasisAssets,
            realized_pnl: realizedPnl,
            unrealized_pnl: totalUnrealizedPnl,
            total_pnl: totalPnl,
            roi_pct: roiPct,
            roi_on_cost_pct: roiOnCostPct
        )
    }

    /// Returns cumulative realized PnL at each sell date for charting (date string, cumulative realized PnL).
    /// Processes trades in date order and emits a point after each sell.
    public func cumulativeRealizedPnlSeries(
        trades: [Trade],
        costBasisMethod: String
    ) -> [(date: String, value: Double)] {
        let sorted = trades.sorted { $0.date < $1.date }
        var result: [(date: String, value: Double)] = []
        var cumulative: Double = 0
        let method = (costBasisMethod == "fifo" || costBasisMethod == "lifo" || costBasisMethod == "average") ? costBasisMethod : "average"

        for asset in Set(sorted.map(\.asset)).filter({ $0 != "USD" }).sorted() {
            var runningCostBasis = 0.0
            var runningUnits = 0.0
            var lots: [(qty: Double, costPerUnit: Double)] = []

            for t in sorted.filter({ $0.asset == asset }) {
                if t.type == "BUY" || t.type == "Transfer" {
                    let qty = t.quantity
                    let totalVal = t.total_value + t.fee
                    let costPerUnit = qty > 0 ? totalVal / qty : 0
                    if costPerUnit > 0, qty > 0 {
                        switch method {
                        case "fifo": lots.append((qty, costPerUnit))
                        case "lifo": lots.insert((qty, costPerUnit), at: 0)
                        default: break
                        }
                        runningUnits += qty
                        runningCostBasis += totalVal
                    }
                } else if t.type == "SELL" {
                    let sellQty = t.quantity
                    let sellProceeds = t.total_value - t.fee
                    var costOfSold = 0.0
                    if method == "average" {
                        if runningUnits > 0 {
                            let avg = runningCostBasis / runningUnits
                            costOfSold = min(sellQty, runningUnits) * avg
                            runningCostBasis -= costOfSold
                        }
                        runningUnits = max(0, runningUnits - sellQty)
                    } else if method == "fifo" {
                        var remaining = sellQty
                        while remaining > 0, !lots.isEmpty {
                            var lot = lots[0]
                            if lot.qty <= remaining {
                                costOfSold += lot.qty * lot.costPerUnit
                                runningCostBasis -= lot.qty * lot.costPerUnit
                                remaining -= lot.qty
                                lots.removeFirst()
                            } else {
                                costOfSold += remaining * lot.costPerUnit
                                runningCostBasis -= remaining * lot.costPerUnit
                                lot.qty -= remaining
                                lots[0] = lot
                                remaining = 0
                            }
                        }
                    } else if method == "lifo" {
                        var remaining = sellQty
                        while remaining > 0, !lots.isEmpty {
                            let idx = lots.count - 1
                            var lot = lots[idx]
                            if lot.qty <= remaining {
                                costOfSold += lot.qty * lot.costPerUnit
                                runningCostBasis -= lot.qty * lot.costPerUnit
                                remaining -= lot.qty
                                lots.removeLast()
                            } else {
                                costOfSold += remaining * lot.costPerUnit
                                runningCostBasis -= remaining * lot.costPerUnit
                                lot.qty -= remaining
                                lots[idx] = lot
                                remaining = 0
                            }
                        }
                    } else {
                        // lifo branch already handled above
                    }
                    let realized = sellProceeds - costOfSold
                    cumulative += realized
                    result.append((t.date, cumulative))
                }
            }
        }
        if result.isEmpty, let first = sorted.first {
            result.append((first.date, 0))
        }
        return result.sorted { $0.date < $1.date }
    }

    /// Realized P&L by calendar period for charting. Period: "month" (e.g. "2024-01") or "quarter" (e.g. "2024-Q1").
    public func realizedPnlByPeriod(
        trades: [Trade],
        costBasisMethod: String,
        period: String
    ) -> [(periodLabel: String, value: Double)] {
        let sells = trades.filter { $0.type == "SELL" }.sorted { $0.date < $1.date }
        var bucket: [String: Double] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        for t in sells {
            guard let pnl = realizedPnlForTrade(trades: trades, tradeId: t.id, costBasisMethod: costBasisMethod),
                  let d = dateFormatter.date(from: t.date) else { continue }
            let key: String
            if period == "quarter" {
                let month = Calendar.current.component(.month, from: d)
                let q = (month - 1) / 3 + 1
                key = String(format: "%d-Q%d", Calendar.current.component(.year, from: d), q)
            } else {
                key = String(format: "%d-%02d", Calendar.current.component(.year, from: d), Calendar.current.component(.month, from: d))
            }
            bucket[key, default: 0] += pnl
        }
        return bucket.keys.sorted().map { (periodLabel: $0, value: bucket[$0] ?? 0) }
    }

    /// Returns realized PnL for a single SELL trade (proceeds - cost of sold), or nil for non-SELL.
    public func realizedPnlForTrade(trades: [Trade], tradeId: String, costBasisMethod: String) -> Double? {
        guard let sellTrade = trades.first(where: { $0.id == tradeId }), sellTrade.type == "SELL" else { return nil }
        let asset = sellTrade.asset
        let sorted = trades.filter { $0.asset == asset }.sorted { $0.date < $1.date }
        let sellIndex = sorted.firstIndex(where: { $0.id == tradeId }) ?? 0
        let upToSell = Array(sorted.prefix(sellIndex + 1))
        let method = (costBasisMethod == "fifo" || costBasisMethod == "lifo" || costBasisMethod == "average") ? costBasisMethod : "average"
        let sellProceeds = sellTrade.total_value - sellTrade.fee
        var costOfSold = 0.0

        if method == "average" {
            var totalCost = 0.0
            var units = 0.0
            for t in upToSell {
                if t.type == "BUY" || t.type == "Transfer" {
                    units += t.quantity
                    totalCost += t.total_value + t.fee
                } else if t.type == "SELL" {
                    let q = t.quantity
                    if units > 0 {
                        let avg = totalCost / units
                        let cost = min(q, units) * avg
                        if t.id == tradeId { costOfSold = cost }
                        totalCost -= cost
                    }
                    units = max(0, units - q)
                }
            }
        } else if method == "fifo" {
            var lots: [(qty: Double, costPerUnit: Double)] = []
            for t in upToSell {
                if t.type == "BUY" || t.type == "Transfer" {
                    let qty = t.quantity
                    let totalVal = t.total_value + t.fee
                    let cpu = qty > 0 ? totalVal / qty : 0
                    if cpu > 0, qty > 0 { lots.append((qty, cpu)) }
                } else if t.type == "SELL" {
                    var remaining = t.quantity
                    while remaining > 0, !lots.isEmpty {
                        var lot = lots[0]
                        if lot.qty <= remaining {
                            if t.id == tradeId { costOfSold += lot.qty * lot.costPerUnit }
                            remaining -= lot.qty
                            lots.removeFirst()
                        } else {
                            let take = remaining
                            if t.id == tradeId { costOfSold += take * lot.costPerUnit }
                            lot.qty -= take
                            lots[0] = lot
                            remaining = 0
                        }
                    }
                }
            }
        } else {
            var lots: [(qty: Double, costPerUnit: Double)] = []
            for t in upToSell {
                if t.type == "BUY" || t.type == "Transfer" {
                    let qty = t.quantity
                    let totalVal = t.total_value + t.fee
                    let cpu = qty > 0 ? totalVal / qty : 0
                    if cpu > 0, qty > 0 { lots.insert((qty, cpu), at: 0) }
                } else if t.type == "SELL" {
                    var remaining = t.quantity
                    while remaining > 0, !lots.isEmpty {
                        let idx = lots.count - 1
                        var lot = lots[idx]
                        if lot.qty <= remaining {
                            if t.id == tradeId { costOfSold += lot.qty * lot.costPerUnit }
                            remaining -= lot.qty
                            lots.removeLast()
                        } else {
                            let take = remaining
                            if t.id == tradeId { costOfSold += take * lot.costPerUnit }
                            lot.qty -= take
                            lots[idx] = lot
                            remaining = 0
                        }
                    }
                }
            }
        }
        return sellProceeds - costOfSold
    }

    /// For each BUY trade, profit from price difference vs previous SELL of same asset:
    /// (previous_sell_price - buy_price) * quantity. Only BUYs with a prior SELL for that asset are included.
    /// Returns dict mapping trade id to buy-profit in USD.
    public func buyProfitPerTrade(trades: [Trade]) -> [String: Double] {
        let sorted = trades.sorted { $0.date < $1.date }
        var lastSellPrice: [String: Double] = [:]
        var result: [String: Double] = [:]
        for t in sorted {
            let asset = t.asset
            if asset == "USD" { continue }
            if t.type == "SELL" {
                if t.price > 0 { lastSellPrice[asset] = t.price }
                continue
            }
            if t.type == "BUY", let prevPrice = lastSellPrice[asset], t.price > 0, t.quantity > 0 {
                result[t.id] = (prevPrice - t.price) * t.quantity
            }
        }
        return result
    }

    // MARK: - Trading analytics (max drawdown, Sharpe, Sortino, win rate)

    /// Builds equity curve (date, value) where value = capital in to date + cumulative realized PnL to date; ends with current total value.
    /// Use `equityCurveSeries` for charting; this internal method is used by computeTradingAnalytics.
    private func equityCurve(trades: [Trade], costBasisMethod: String, currentTotalValue: Double) -> [(date: String, value: Double)] {
        let sorted = trades.sorted { $0.date < $1.date }
        guard let firstDate = sorted.first?.date else { return [] }
        var capitalIn: [String: Double] = [:]
        var runningCapital = 0.0
        for t in sorted {
            if t.asset == "USD" {
                if t.type == "Deposit" { runningCapital += t.quantity }
                else if t.type == "Withdrawal" { runningCapital -= t.quantity }
            }
            capitalIn[t.date] = runningCapital
        }
        let cumRealized = cumulativeRealizedPnlSeries(trades: trades, costBasisMethod: costBasisMethod)
        var points: [(date: String, value: Double)] = []
        var lastCapital = 0.0
        for (date, cum) in cumRealized {
            let cap = capitalIn[date] ?? lastCapital
            lastCapital = cap
            points.append((date, cap + cum))
        }
        if points.isEmpty {
            let cap0 = capitalIn[firstDate] ?? 0
            points.append((firstDate, cap0))
        }
        points.append(("__now__", currentTotalValue))
        return points
    }

    /// Public API for charting: equity curve (date, value). Date "__now__" is replaced with current date in ISO format.
    public func equityCurveSeries(
        trades: [Trade],
        costBasisMethod: String,
        currentTotalValue: Double
    ) -> [(date: String, value: Double)] {
        let curve = equityCurve(trades: trades, costBasisMethod: costBasisMethod, currentTotalValue: currentTotalValue)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        let nowStr = f.string(from: Date())
        return curve.map { $0.date == "__now__" ? (date: String(nowStr), value: $0.value) : $0 }
    }

    /// Drawdown at each point: (date, drawdown) where drawdown = running peak - value. For charting.
    public func drawdownSeries(fromEquityCurve equityPoints: [(date: String, value: Double)]) -> [(date: String, value: Double)] {
        var peak = 0.0
        return equityPoints.map { point in
            if point.value > peak { peak = point.value }
            return (date: point.date, value: peak - point.value)
        }
    }

    /// Computes max drawdown (USD and %) from equity curve.
    private func maxDrawdown(from values: [Double]) -> (dd: Double, ddPct: Double) {
        var peak = 0.0
        var maxDd = 0.0
        for v in values {
            if v > peak { peak = v }
            let dd = peak - v
            if dd > maxDd { maxDd = dd }
        }
        let pct = peak > 0 ? (maxDd / peak * 100) : 0
        return (maxDd, pct)
    }

    /// Period returns from equity curve (value[i] - value[i-1]) / value[i-1].
    private func periodReturns(from values: [Double]) -> [Double] {
        var returns: [Double] = []
        for i in 1..<values.count {
            let prev = values[i - 1]
            if prev > 0 {
                returns.append((values[i] - prev) / prev)
            }
        }
        return returns
    }

    /// Sharpe ratio (mean / std); risk-free rate 0. Returns nil if no variance or no returns.
    private func sharpe(returns: [Double]) -> Double? {
        guard returns.count > 1 else { return nil }
        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(returns.count - 1)
        let std = variance > 0 ? sqrt(variance) : 0
        guard std > 0 else { return nil }
        return mean / std
    }

    /// Sortino ratio (mean / downside deviation). Downside deviation = sqrt(mean(min(r,0)^2)).
    private func sortino(returns: [Double]) -> Double? {
        guard !returns.isEmpty else { return nil }
        let mean = returns.reduce(0, +) / Double(returns.count)
        let downsideSq = returns.map { let d = min($0, 0); return d * d }.reduce(0, +) / Double(returns.count)
        let downside = downsideSq > 0 ? sqrt(downsideSq) : 0
        guard downside > 0 else { return nil }
        return mean / downside
    }

    /// Trading analytics: max drawdown, Sharpe, Sortino, win rate, trade counts.
    public func computeTradingAnalytics(
        trades: [Trade],
        costBasisMethod: String,
        currentTotalValue: Double
    ) -> TradingAnalytics {
        let curve = equityCurve(trades: trades, costBasisMethod: costBasisMethod, currentTotalValue: currentTotalValue)
        let values = curve.map(\.value)
        let (maxDd, maxDdPct) = maxDrawdown(from: values)
        let returns = periodReturns(from: values)
        let sharpeVal = sharpe(returns: returns)
        let sortinoVal = sortino(returns: returns)

        let sellPnl = Dictionary(uniqueKeysWithValues: trades.filter { $0.type == "SELL" }.compactMap { t -> (String, Double)? in
            guard let pnl = realizedPnlForTrade(trades: trades, tradeId: t.id, costBasisMethod: costBasisMethod) else { return nil }
            return (t.id, pnl)
        })
        let buyPnl = buyProfitPerTrade(trades: trades)
        var wins = 0, losses = 0
        for t in trades {
            let pnl: Double?
            if t.type == "SELL" { pnl = sellPnl[t.id] }
            else if t.type == "BUY" { pnl = buyPnl[t.id] }
            else { pnl = nil }
            guard let p = pnl else { continue }
            if p > 0 { wins += 1 }
            else if p < 0 { losses += 1 }
        }
        let totalWithPnl = wins + losses
        let winRatePct = totalWithPnl > 0 ? (Double(wins) / Double(totalWithPnl) * 100) : nil

        let totalTrades = trades.filter { $0.type == "BUY" || $0.type == "SELL" }.count

        let vol = volatility(returns: returns)

        return TradingAnalytics(
            max_drawdown: maxDd,
            max_drawdown_pct: maxDdPct,
            sharpe_ratio: sharpeVal,
            sortino_ratio: sortinoVal,
            win_rate_pct: winRatePct,
            total_trades: totalTrades,
            winning_trades: wins,
            losing_trades: losses,
            realized_volatility: vol
        )
    }

    /// Standard deviation of returns; nil if fewer than 2 returns.
    private func volatility(returns: [Double]) -> Double? {
        guard returns.count >= 2 else { return nil }
        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(returns.count - 1)
        return variance > 0 ? sqrt(variance) : nil
    }

    /// Rolling volatility series: (date, volatility) from equity curve period returns. Window = number of points.
    public func rollingVolatilitySeries(
        trades: [Trade],
        costBasisMethod: String,
        currentTotalValue: Double,
        windowSize: Int = 30
    ) -> [(date: String, value: Double)] {
        let curve = equityCurveSeries(trades: trades, costBasisMethod: costBasisMethod, currentTotalValue: currentTotalValue)
        let values = curve.map(\.value)
        guard values.count >= 2, windowSize >= 2 else { return [] }
        var returns: [Double] = []
        for i in 1..<values.count {
            let prev = values[i - 1]
            if prev > 0 { returns.append((values[i] - prev) / prev) }
        }
        guard returns.count >= windowSize else { return [] }
        var result: [(date: String, value: Double)] = []
        for i in (windowSize - 1)..<returns.count {
            let window = Array(returns[(i - windowSize + 1)...i])
            guard let vol = volatility(returns: window) else { continue }
            let dateIndex = i + 1
            if dateIndex < curve.count {
                result.append((curve[dateIndex].date, vol))
            }
        }
        return result
    }

    /// Open tax lots per asset with acquisition date. Returns (asset, qty, costPerUnit, dateString) for FIFO/LIFO; for Average, one effective lot per asset.
    public func openLotsWithDates(trades: [Trade], asset: String, costBasisMethod: String) -> [(qty: Double, costPerUnit: Double, date: String)] {
        let assetTrades = trades.filter { $0.asset == asset }.sorted { $0.date < $1.date }
        if costBasisMethod.lowercased() == "average" {
            var totalQty = 0.0
            var totalCost = 0.0
            var firstDate: String?
            for t in assetTrades {
                if t.type == "BUY" || t.type == "Transfer", t.quantity > 0 {
                    totalQty += t.quantity
                    totalCost += (t.total_value + t.fee)
                    if firstDate == nil { firstDate = t.date }
                } else if t.type == "SELL" { totalQty -= t.quantity }
            }
            guard totalQty > 0, totalCost > 0, let date = firstDate else { return [] }
            return [(totalQty, totalCost / totalQty, date)]
        }
        var lots: [(qty: Double, costPerUnit: Double, date: String)] = []
        for t in assetTrades {
            if t.type == "BUY" || t.type == "Transfer" {
                let qty = t.quantity
                let totalVal = t.total_value + t.fee
                let costPerUnit = qty > 0 ? totalVal / qty : 0
                if costPerUnit > 0, qty > 0 { lots.append((qty, costPerUnit, t.date)) }
            } else if t.type == "SELL" {
                var sellQty = t.quantity
                if costBasisMethod.lowercased() == "lifo" {
                    while sellQty > 0, !lots.isEmpty {
                        let idx = lots.count - 1
                        if lots[idx].qty <= sellQty {
                            sellQty -= lots[idx].qty
                            lots.removeLast()
                        } else {
                            lots[idx].qty -= sellQty
                            sellQty = 0
                        }
                    }
                } else {
                    while sellQty > 0, !lots.isEmpty {
                        if lots[0].qty <= sellQty {
                            sellQty -= lots[0].qty
                            lots.removeFirst()
                        } else {
                            lots[0].qty -= sellQty
                            sellQty = 0
                        }
                    }
                }
            }
        }
        return lots.filter { $0.qty > 0 }
    }

    // MARK: - Hold time and rolling Sharpe for additional charts

    /// Returns hold time in days for each closed lot (FIFO: each sell consumes buys in order).
    /// One entry per closed quantity unit (approximated by emitting one days-held value per sell, using average buy date for consumed lots).
    public func holdTimesInDays(trades: [Trade]) -> [Double] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        var result: [Double] = []
        for asset in Set(trades.map(\.asset)).filter({ $0 != "USD" }) {
            let assetTrades = trades.filter { $0.asset == asset }.sorted { $0.date < $1.date }
            var fifo: [(qty: Double, date: Date)] = []
            guard assetTrades.first.flatMap({ f.date(from: $0.date) }) != nil else { continue }  // need at least one parseable date
            for t in assetTrades {
                guard let date = f.date(from: t.date) else { continue }
                if t.type == "BUY" || t.type == "Transfer" {
                    let qty = t.quantity
                    if qty > 0 { fifo.append((qty, date)) }
                } else if t.type == "SELL" {
                    var remaining = t.quantity
                    while remaining > 0, !fifo.isEmpty {
                        var lot = fifo[0]
                        let take = min(remaining, lot.qty)
                        let days = date.timeIntervalSince(lot.date) / 86400
                        result.append(days)
                        remaining -= take
                        lot.qty -= take
                        if lot.qty <= 0 { fifo.removeFirst() }
                        else { fifo[0] = lot }
                    }
                }
            }
        }
        return result
    }

    /// Rolling Sharpe ratio series: (end date of window, Sharpe value). Window = number of equity curve points (e.g. 30).
    /// Uses equity curve and period returns; each point is the Sharpe over the preceding window.
    public func rollingSharpeSeries(
        trades: [Trade],
        costBasisMethod: String,
        currentTotalValue: Double,
        windowSize: Int = 30
    ) -> [(date: String, value: Double)] {
        let curve = equityCurveSeries(trades: trades, costBasisMethod: costBasisMethod, currentTotalValue: currentTotalValue)
        let values = curve.map(\.value)
        guard values.count >= 2, windowSize >= 2 else { return [] }
        var returns: [Double] = []
        for i in 1..<values.count {
            let prev = values[i - 1]
            if prev > 0 { returns.append((values[i] - prev) / prev) }
        }
        guard returns.count >= windowSize else { return [] }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        var result: [(date: String, value: Double)] = []
        for i in (windowSize - 1)..<returns.count {
            let window = Array(returns[(i - windowSize + 1)...i])
            guard let sharpeVal = sharpe(returns: window) else { continue }
            let dateIndex = i + 1
            if dateIndex < curve.count {
                result.append((curve[dateIndex].date, sharpeVal))
            }
        }
        return result
    }

    // MARK: - Correlation matrix (pairwise return correlation)

    /// Computes pairwise Pearson correlation of return series. Use for correlation matrix / heatmap.
    /// - Parameter returnSeries: Map asset symbol → array of period returns (e.g. daily). All series are trimmed to the minimum length so pairs are aligned.
    /// - Returns: Correlation matrix with assets in sorted order, or nil if fewer than 2 assets or insufficient data (need at least 2 aligned returns per asset).
    public func computeCorrelationMatrix(returnSeries: [String: [Double]]) -> CorrelationMatrix? {
        let assets = returnSeries.keys.sorted()
        guard assets.count >= 2 else { return nil }
        let minLen = returnSeries.values.map(\.count).min() ?? 0
        guard minLen >= 2 else { return nil }
        // Align: take last minLen returns for each asset (so all same length).
        var aligned: [String: [Double]] = [:]
        for a in assets {
            guard let r = returnSeries[a], r.count >= minLen else { continue }
            aligned[a] = Array(r.suffix(minLen))
        }
        let ordered = aligned.keys.sorted()
        guard ordered.count >= 2 else { return nil }
        let n = ordered.count
        var matrix: [[Double]] = (0..<n).map { i in (0..<n).map { _ in 0.0 } }
        for i in 0..<n {
            matrix[i][i] = 1.0
            guard let seriesI = aligned[ordered[i]] else { continue }
            for j in (i + 1)..<n {
                guard let seriesJ = aligned[ordered[j]] else { continue }
                let corr = pearsonCorrelation(a: seriesI, b: seriesJ)
                matrix[i][j] = corr
                matrix[j][i] = corr
            }
        }
        return CorrelationMatrix(assets: ordered, matrix: matrix)
    }

    /// Pearson correlation between two equal-length return series. Returns value in [-1, 1] or 0 if undefined.
    private func pearsonCorrelation(a: [Double], b: [Double]) -> Double {
        guard a.count == b.count, a.count >= 2 else { return 0 }
        let n = Double(a.count)
        let meanA = a.reduce(0, +) / n
        let meanB = b.reduce(0, +) / n
        var sumCov = 0.0
        var sumSqA = 0.0
        var sumSqB = 0.0
        for i in 0..<a.count {
            let da = a[i] - meanA
            let db = b[i] - meanB
            sumCov += da * db
            sumSqA += da * da
            sumSqB += db * db
        }
        let denom = sqrt(sumSqA * sumSqB)
        guard denom > 0 else { return 0 }
        let r = sumCov / denom
        return max(-1, min(1, r))
    }
}
