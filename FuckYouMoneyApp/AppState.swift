import Foundation
import SwiftUI
import UserNotifications
import FuckYouMoneyCore

/// User-defined alert rule. Stored in UserDefaults.
struct AlertRule: Codable, Equatable, Identifiable {
    var id: String
    var type: String  // portfolio_value_below, portfolio_value_above, asset_pct_down_24h, drawdown_above_pct, asset_pct_of_portfolio_above
    var value: Double
    var asset: String?
    var enabled: Bool
}

@MainActor
final class AppState: ObservableObject {
    @Published var currentUser: String = "Default"
    @Published var users: [String] = []
    @Published var data: AppData = AppData()
    @Published var selectedGroupId: String?
    @Published var selectedAccountId: String?
    @Published var priceCache: [String: [String: Any]] = [:]
    @Published var portfolioMetrics: PortfolioMetrics?
    @Published var tradingAnalytics: TradingAnalytics?
    @Published var errorMessage: String?
    @Published var isLoading = false
    /// In-memory activity log (trade add, user switch, export/import). Shown in Dashboard.
    @Published var activityLog: [String] = []
    /// Alerts that have fired (rule id + message). Shown in Dashboard; cleared when user dismisses.
    @Published var triggeredAlerts: [(id: String, message: String)] = []

    /// Trading tab: balance and fee/volume from exchange API.
    @Published var tradingBalances: BalanceInfo?
    @Published var tradingFeeTier: FeeTierInfo?
    @Published var tradingVolume30d: Double?
    @Published var tradingLoadError: String?
    @Published var tradingOrderMessage: String?

    /// When set by Assets tab "Add trade…", ContentView switches to Transactions and this is consumed to pre-fill asset.
    @Published var pendingAddTradeAsset: String?

    var storage: StorageService!
    private let pricing = PricingService()
    private let metrics = MetricsService()
    private var apiServer: LocalAPIServer?

    static let apiEnabledKey = "FuckYouMoney.apiEnabled"
    static let apiPortKey = "FuckYouMoney.apiPort"
    static let webhookURLKey = "FuckYouMoney.webhookURL"
    static let alertsEnabledKey = "FuckYouMoney.alertsEnabled"
    static let alertRulesKey = "FuckYouMoney.alertRules"
    static let dataDirectoryKey = "FuckYouMoney.dataDirectoryPath"
    var apiEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.apiEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.apiEnabledKey); if newValue { startAPIServer() } else { stopAPIServer() } }
    }
    var apiPort: Int {
        get { let p = UserDefaults.standard.object(forKey: Self.apiPortKey) as? Int; return p ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: Self.apiPortKey); if apiEnabled { startAPIServer() } }
    }
    /// Webhook URL to POST when trades are added or portfolio is refreshed (e.g. for Crank or Slack). Empty = disabled.
    var webhookURL: String? {
        get {
            let s = UserDefaults.standard.string(forKey: Self.webhookURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.flatMap { $0.isEmpty ? nil : $0 }
        }
        set { UserDefaults.standard.set(newValue?.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.webhookURLKey) }
    }
    var alertsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.alertsEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.alertsEnabledKey) }
    }
    var alertRules: [AlertRule] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.alertRulesKey),
                  let decoded = try? JSONDecoder().decode([AlertRule].self, from: data) else { return [] }
            return decoded
        }
        set { try? UserDefaults.standard.set(JSONEncoder().encode(newValue), forKey: Self.alertRulesKey) }
    }
    /// When true, a local notification is sent when new noteworthy (crypto-impact) news items appear on Dashboard refresh.
    var newsNotificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.newsNotificationsEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.newsNotificationsEnabledKey) }
    }
    /// Links we have already notified for (capped). Used to avoid duplicate notifications.
    private var noteworthyNotifiedLinks: [String] {
        get {
            (UserDefaults.standard.array(forKey: Self.noteworthyNotifiedLinksKey) as? [String]) ?? []
        }
        set {
            let trimmed = Array(newValue.suffix(80))
            UserDefaults.standard.set(trimmed, forKey: Self.noteworthyNotifiedLinksKey)
        }
    }
    /// Custom data directory path (e.g. repo root for Python compatibility). Nil = use Application Support.
    var customDataDirectoryPath: String? {
        get { UserDefaults.standard.string(forKey: Self.dataDirectoryKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.dataDirectoryKey) }
    }
    /// Current base URL used for storage (for display in Settings).
    var currentDataDirectoryURL: URL {
        if let path = customDataDirectoryPath, !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FuckYouMoney", isDirectory: true)
    }

    init() {
        let baseURL = Self.resolveBaseURL()
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        storage = StorageService(paths: DataPathProvider(baseURL: baseURL))
    }

    private static func resolveBaseURL() -> URL {
        if let path = UserDefaults.standard.string(forKey: dataDirectoryKey), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FuckYouMoney", isDirectory: true)
    }

    /// Switch to a custom data directory (e.g. folder containing crypto_data_default.json from Python). Reloads data.
    func setDataDirectory(url: URL?) {
        stopAPIServer()
        if let url = url {
            customDataDirectoryPath = url.path
        } else {
            customDataDirectoryPath = nil
        }
        let baseURL = Self.resolveBaseURL()
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        storage = StorageService(paths: DataPathProvider(baseURL: baseURL))
        load()
        if apiEnabled { startAPIServer() }
    }

    func load() {
        users = storage.loadUsers()
        if users.isEmpty { users = ["Default"]; try? storage.saveUsers(users) }
        if !users.contains(currentUser) { currentUser = users[0] }
        activityLog.removeAll()
        do {
            data = try storage.loadData(username: currentUser)
            priceCache = StorageService.normalizePriceCacheKeys(storage.loadPriceCache())
            recomputeMetrics()
            appendActivity("Loaded: \(currentUser)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func appendActivity(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        activityLog.append("[\(formatter.string(from: Date()))] \(message)")
        if activityLog.count > 500 { activityLog.removeFirst(100) }
    }

    func save() {
        do {
            try storage.saveData(data, username: currentUser)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Canonical key for price cache so "BNB" and "bnb" resolve to the same entry.
    private static func priceCacheKey(asset: String) -> String {
        asset.uppercased()
    }

    /// Normalize loaded price cache keys to uppercase so lookups by any casing succeed.
    func recomputeMetrics() {
        let trades = filteredTrades()
        func getPrice(_ asset: String) -> Double? {
            if asset.uppercased() == "USDC" || asset.uppercased() == "USDT" { return 1.0 }
            if let entry = priceCache[Self.priceCacheKey(asset: asset)], let p = entry["price"] as? Double { return p }
            return nil
        }
        portfolioMetrics = metrics.computePortfolioMetrics(trades: trades, costBasisMethod: data.settings.cost_basis_method, getCurrentPrice: getPrice)
        let totalValue = portfolioMetrics?.total_value ?? 0
        tradingAnalytics = metrics.computeTradingAnalytics(trades: trades, costBasisMethod: data.settings.cost_basis_method, currentTotalValue: totalValue)
    }

    /// Returns 24h % change for an asset from price cache, or nil if not available. USDC/USDT return 0.
    /// Lookup uses canonical (uppercase) key first; falls back to raw key so BNB/bnb and other variants match.
    func pctChange24h(asset: String) -> Double? {
        if asset.uppercased() == "USDC" || asset.uppercased() == "USDT" { return 0 }
        let canonical = Self.priceCacheKey(asset: asset)
        for key in [canonical, asset, asset.lowercased(), asset.uppercased()] {
            if let entry = priceCache[key], let pct = entry["pct_change_24h"] as? Double { return pct }
        }
        return nil
    }

    /// Portfolio 24h USD change: sum over assets of (current_value - value_24h_ago) using 24h % from cache.
    func portfolio24hUsd() -> Double? {
        guard let m = portfolioMetrics else { return nil }
        var total: Double = 0
        var hasAny = false
        for (asset, pa) in m.per_asset {
            guard let pct = pctChange24h(asset: asset), pa.current_value > 0 else { continue }
            let value24hAgo = pa.current_value / (1 + pct / 100)
            total += pa.current_value - value24hAgo
            hasAny = true
        }
        return hasAny ? total : nil
    }

    /// Per-account (value, pnl) for current scope. When scope is All or Group, returns one row per account in scope.
    func perAccountMetricsInScope() -> [(accountId: String, accountName: String, value: Double, pnl: Double)] {
        let accountsInScope: [Account]
        if let aid = selectedAccountId {
            if let acc = data.accounts.first(where: { $0.id == aid }) {
                accountsInScope = [acc]
            } else {
                accountsInScope = []
            }
        } else if let gid = selectedGroupId, let group = data.account_groups.first(where: { $0.id == gid }) {
            accountsInScope = data.accounts.filter { group.accounts.contains($0.id) }
        } else {
            accountsInScope = data.accounts
        }
        func getPrice(_ asset: String) -> Double? {
            if asset.uppercased() == "USDC" || asset.uppercased() == "USDT" { return 1.0 }
            if let entry = priceCache[Self.priceCacheKey(asset: asset)], let p = entry["price"] as? Double { return p }
            return nil
        }
        return accountsInScope.map { acc in
            let tradesForAccount = data.trades.filter { $0.account_id == acc.id }
            let m = metrics.computePortfolioMetrics(trades: tradesForAccount, costBasisMethod: data.settings.cost_basis_method, getCurrentPrice: getPrice)
            return (acc.id, acc.name, m.total_value, m.total_pnl)
        }
    }

    func filteredTrades() -> [Trade] {
        let all = data.trades
        if let aid = selectedAccountId {
            return all.filter { $0.account_id == aid }
        }
        if let gid = selectedGroupId,
           let group = data.account_groups.first(where: { $0.id == gid }) {
            let ids = Set(group.accounts)
            return all.filter { ids.contains($0.account_id ?? "") }
        }
        return all
    }

    /// Current holding (net quantity) for an asset in an account. Used for quick-add % quantity.
    func holdingQty(asset: String, accountId: String?) -> Double {
        let relevant = data.trades.filter { t in
            t.asset == asset && (accountId == nil || t.account_id == accountId)
        }
        return relevant.reduce(0.0) { sum, t in
            switch t.type {
            case "BUY", "Transfer", "Deposit": return sum + t.quantity
            case "SELL", "Withdrawal": return sum - t.quantity
            default: return sum
            }
        }
    }

    /// What-if scenario: apply price shocks (asset -> multiplier, e.g. BTC -> 0.8 for -20%). Returns (new portfolio value, delta from current).
    func scenarioPortfolioValue(shocks: [String: Double]) -> (newValue: Double, delta: Double) {
        guard let m = portfolioMetrics else { return (0, 0) }
        var newValue = m.usd_balance
        for (asset, per) in m.per_asset {
            let mult = shocks[asset.uppercased()] ?? 1.0
            let currentVal = per.current_value
            let shockedVal = (per.price ?? 0) > 0 ? (currentVal * mult) : currentVal
            newValue += shockedVal
        }
        let delta = newValue - m.total_value
        return (newValue, delta)
    }

    /// Open tax lots for display/export. Returns (asset, qty, costPerUnit, date) array for all assets with holdings.
    func taxLotRows() -> [(asset: String, qty: Double, costPerUnit: Double, date: String)] {
        let assets = Set(filteredTrades().map(\.asset)).filter { $0 != "USD" }
        var rows: [(asset: String, qty: Double, costPerUnit: Double, date: String)] = []
        for asset in assets.sorted() {
            let lots = metrics.openLotsWithDates(trades: filteredTrades(), asset: asset, costBasisMethod: data.settings.cost_basis_method)
            for lot in lots {
                rows.append((asset: asset, qty: lot.qty, costPerUnit: lot.costPerUnit, date: lot.date))
            }
        }
        return rows
    }

    /// Benchmark vs BTC: portfolio equity curve and a "100% BTC" curve (same initial capital). BTC curve has two points (first date, initial value) and (now, initial * currentBtc / btcFirst). Returns nil for btc curve if historical BTC price unavailable.
    func benchmarkBTCSeries() async -> (portfolio: [(date: String, value: Double)], btc: [(date: String, value: Double)]?) {
        let trades = filteredTrades()
        guard let totalValue = portfolioMetrics?.total_value else { return ([], nil) }
        let curve = metrics.equityCurveSeries(trades: trades, costBasisMethod: data.settings.cost_basis_method, currentTotalValue: totalValue)
        guard let first = curve.first, let last = curve.last else { return (curve, nil) }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let firstDate = formatter.date(from: first.date) else { return (curve, nil) }
        let btcFirst = await pricing.fetchHistoricalPrice(asset: "BTC", date: firstDate)
        let btcCurrent = currentPrice(asset: "BTC")
        guard let b0 = btcFirst, let bc = btcCurrent, b0 > 0 else { return (curve, nil) }
        let initialCapital = first.value
        let btcNowValue = initialCapital * (bc / b0)
        let btcCurve = [(first.date, initialCapital), (last.date, btcNowValue)]
        return (curve, btcCurve)
    }

    /// CSV string for tax export: trades in the given year with cost basis and realized gain/loss (for sells).
    func exportTradesForYearCSV(year: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let tradesInYear = filteredTrades().filter { trade in
            guard let d = formatter.date(from: String(trade.date.prefix(19))) else { return false }
            return Calendar.current.component(.year, from: d) == year
        }
        var csv = "Date,Asset,Type,Quantity,Price,Cost Basis,Realized Gain/Loss,Fee,Exchange\n"
        for t in tradesInYear.sorted(by: { $0.date < $1.date }) {
            let costBasis: String
            let realized: String
            if t.type == "SELL" {
                let pnl = metrics.realizedPnlForTrade(trades: filteredTrades(), tradeId: t.id, costBasisMethod: data.settings.cost_basis_method)
                costBasis = pnl != nil ? String(format: "%.2f", (t.quantity * t.price) - (pnl ?? 0)) : ""
                realized = pnl != nil ? String(format: "%.2f", pnl!) : ""
            } else {
                costBasis = String(format: "%.2f", t.total_value + t.fee)
                realized = ""
            }
            let row = "\(t.date),\(t.asset),\(t.type),\(t.quantity),\(t.price),\(costBasis),\(realized),\(t.fee),\(t.exchange)"
            csv += row + "\n"
        }
        return csv
    }

    /// Last N trades that have source or strategy_id set (API-originated, e.g. from Crank). Newest first.
    func recentAPIOriginTrades(limit: Int = 10) -> [Trade] {
        data.trades
            .filter { $0.source != nil || $0.strategy_id != nil }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }

    /// Current market price for an asset from price cache (nil if not available).
    func currentPrice(asset: String) -> Double? {
        if asset.uppercased() == "USD" || asset.uppercased() == "USDC" || asset.uppercased() == "USDT" { return 1.0 }
        return priceCache[Self.priceCacheKey(asset: asset)]?["price"] as? Double
    }

    /// Available USDC + USDT + USD for an account (for BUY quantity max).
    func availableUsdcUsd(accountId: String?) -> Double {
        holdingQty(asset: "USDC", accountId: accountId) + holdingQty(asset: "USDT", accountId: accountId) + holdingQty(asset: "USD", accountId: accountId)
    }

    /// Fee from exchange settings: totalValue * (rate/100). Limit → maker, Market → taker.
    func computedFee(totalValue: Double, exchange: String, orderType: String) -> Double {
        guard let fees = data.settings.fee_structure[exchange] else { return 0 }
        let rate = orderType.lowercased().hasPrefix("limit") ? fees.maker : fees.taker
        return totalValue * (rate / 100.0)
    }

    /// One row for Client P&L Summary: (Client name, Your %, Client P&L, Your Share).
    struct ClientPnlRow {
        let clientName: String
        let yourPct: Double
        let clientPnl: Double
        let yourShare: Double
    }

    /// Rows for the Client P&L Summary table. If current user is client, one row; else one row per other user with is_client true.
    func clientPnlRows() -> [ClientPnlRow] {
        func getPrice(_ asset: String) -> Double? {
            if asset.uppercased() == "USDC" || asset.uppercased() == "USDT" { return 1.0 }
            return priceCache[asset]?["price"] as? Double
        }
        func pnlForTrades(_ trades: [Trade], totalValue: Double) -> Double {
            let buyCost = trades.filter { $0.type == "BUY" || $0.type == "Transfer" }.reduce(0.0) { $0 + $1.total_value + $1.fee }
            let sellProceeds = trades.filter { $0.type == "SELL" }.reduce(0.0) { $0 + $1.total_value - $1.fee }
            return totalValue + sellProceeds - buyCost
        }
        if data.settings.is_client {
            let trades = data.trades
            let totalValue = portfolioMetrics?.total_value ?? 0
            let clientPnl = pnlForTrades(trades, totalValue: totalValue)
            let pct = data.settings.client_percentage
            return [ClientPnlRow(clientName: currentUser, yourPct: pct, clientPnl: clientPnl, yourShare: clientPnl * (pct / 100))]
        }
        var rows: [ClientPnlRow] = []
        for username in users {
            guard let clientData = try? storage.loadData(username: username), clientData.settings.is_client else { continue }
            let trades = clientData.trades
            if trades.isEmpty { continue }
            let m = metrics.computePortfolioMetrics(trades: trades, costBasisMethod: clientData.settings.cost_basis_method, getCurrentPrice: getPrice)
            let clientPnl = pnlForTrades(trades, totalValue: m.total_value)
            let pct = clientData.settings.client_percentage
            rows.append(ClientPnlRow(clientName: username, yourPct: pct, clientPnl: clientPnl, yourShare: clientPnl * (pct / 100)))
        }
        return rows
    }

    func refreshPrices() async {
        isLoading = true
        defer { isLoading = false }
        let assets = Set(data.trades.map(\.asset)).filter { $0 != "USD" && $0 != "USDC" && $0 != "USDT" }
        for asset in assets {
            let (price, pct) = await pricing.fetchPriceAnd24h(asset: asset)
            if let price = price {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                var entry: [String: Any] = ["price": price, "timestamp": f.string(from: Date())]
                if let pct = pct { entry["pct_change_24h"] = pct }
                priceCache[Self.priceCacheKey(asset: asset)] = entry
            }
        }
        storage.savePriceCache(priceCache)
        recordPriceHistory(assets: Array(assets))
        recomputeMetrics()
        fireWebhook(event: "portfolio_refreshed", trades: nil)
        evaluateAlerts()
    }

    /// Appends today's price for each asset to price history and trims to last 365 days per asset.
    private func recordPriceHistory(assets: [String]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        var history = storage.loadPriceHistory()
        for asset in assets {
            let key = Self.priceCacheKey(asset: asset)
            guard let entry = priceCache[key], let price = entry["price"] as? Double else { continue }
            var dates = history[asset] ?? [:]
            dates[today] = price
            let sortedDates = dates.keys.sorted()
            if sortedDates.count > 365 {
                let toKeep = Set(sortedDates.suffix(365))
                dates = dates.filter { toKeep.contains($0.key) }
            }
            history[asset] = dates
        }
        storage.savePriceHistory(history)
    }

    /// Evaluate alert rules and fire webhook/notification for any that trigger.
    private func evaluateAlerts() {
        guard alertsEnabled else { return }
        let rules = alertRules.filter(\.enabled)
        guard !rules.isEmpty else { return }
        let totalValue = portfolioMetrics?.total_value ?? 0
        let maxDdPct = tradingAnalytics?.max_drawdown_pct ?? 0
        for rule in rules {
            var triggered = false
            var message = ""
            switch rule.type {
            case "portfolio_value_below":
                if totalValue < rule.value {
                    triggered = true
                    message = "Portfolio value \(totalValue) is below \(rule.value)"
                }
            case "portfolio_value_above":
                if totalValue > rule.value {
                    triggered = true
                    message = "Portfolio value \(totalValue) is above \(rule.value)"
                }
            case "asset_pct_down_24h":
                if let asset = rule.asset, let entry = priceCache[Self.priceCacheKey(asset: asset)], let pct = entry["pct_change_24h"] as? Double, pct <= -abs(rule.value) {
                    triggered = true
                    message = "\(asset) is down \(String(format: "%.1f", pct))% in 24h"
                }
            case "drawdown_above_pct":
                if maxDdPct >= rule.value {
                    triggered = true
                    message = "Max drawdown \(String(format: "%.1f", maxDdPct))% is above \(rule.value)%"
                }
            case "asset_pct_of_portfolio_above":
                if let asset = rule.asset, let m = portfolioMetrics?.per_asset[asset], totalValue > 0 {
                    let pct = (m.current_value / totalValue) * 100
                    if pct >= rule.value {
                        triggered = true
                        message = "\(asset) is \(String(format: "%.1f", pct))% of portfolio (above \(rule.value)%)"
                    }
                }
            default:
                break
            }
            if triggered, !triggeredAlerts.contains(where: { $0.id == rule.id }) {
                triggeredAlerts.append((id: rule.id, message: message))
                struct AlertPayload: Encodable { let event: String; let rule_id: String; let message: String }
                if let urlString = webhookURL, let url = URL(string: urlString), url.scheme == "http" || url.scheme == "https" {
                    let payload = AlertPayload(event: "alert", rule_id: rule.id, message: message)
                    if let body = try? JSONEncoder().encode(payload) {
                        var req = URLRequest(url: url)
                        req.httpMethod = "POST"
                        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        req.httpBody = body
                        Task.detached(priority: .utility) { _ = try? await URLSession.shared.data(for: req) }
                    }
                }
                let content = UNMutableNotificationContent()
                content.title = "FuckYouMoney Alert"
                content.body = message
                content.sound = .default
                let request = UNNotificationRequest(identifier: "alert-\(rule.id)-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
            }
        }
    }

    /// If news notifications are enabled, notifies for new noteworthy items (by link). Capped at 3 per run; stores notified links to avoid repeats.
    func checkAndNotifyNoteworthyNews(items: [(title: String, link: String)]) {
        guard newsNotificationsEnabled else { return }
        let notifiedSet = Set(noteworthyNotifiedLinks)
        let newItems = items.filter { !$0.link.isEmpty && !notifiedSet.contains($0.link) }
        let toNotify = Array(newItems.prefix(3))
        guard !toNotify.isEmpty else { return }
        for item in toNotify {
            let content = UNMutableNotificationContent()
            content.title = "Noteworthy news"
            content.body = item.title
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "noteworthy-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
        noteworthyNotifiedLinks = noteworthyNotifiedLinks + toNotify.map(\.link)
    }

    /// Returns pairwise correlation matrix for held assets from stored price history; nil if fewer than 2 assets or insufficient aligned days.
    func loadCorrelationMatrix() async -> CorrelationMatrix? {
        let history = storage.loadPriceHistory()
        guard let pm = portfolioMetrics else { return nil }
        let heldAssets = pm.per_asset.keys.filter { asset in
            let pa = pm.per_asset[asset]!
            return (pa.units_held + pa.holding_qty) > 0
        }.filter { history[$0] != nil && (history[$0]?.count ?? 0) >= 2 }
        guard heldAssets.count >= 2 else { return nil }
        var commonDates: Set<String>?
        for asset in heldAssets {
            let dates = Set(history[asset]!.keys)
            if commonDates == nil { commonDates = dates }
            else { commonDates = commonDates!.intersection(dates) }
        }
        guard let dates = commonDates, dates.count >= 2 else { return nil }
        let sortedDates = dates.sorted()
        var returnSeries: [String: [Double]] = [:]
        for asset in heldAssets {
            let prices = history[asset]!
            var returns: [Double] = []
            for i in 1..<sortedDates.count {
                let d0 = sortedDates[i - 1], d1 = sortedDates[i]
                guard let p0 = prices[d0], let p1 = prices[d1], p0 > 0 else { continue }
                returns.append((p1 - p0) / p0)
            }
            if returns.count >= 2 { returnSeries[asset] = returns }
        }
        guard returnSeries.count >= 2 else { return nil }
        return metrics.computeCorrelationMatrix(returnSeries: returnSeries)
    }

    /// Synchronous version for the API handler (same logic as loadCorrelationMatrix).
    func correlationMatrixSync() -> CorrelationMatrix? {
        let history = storage.loadPriceHistory()
        guard let pm = portfolioMetrics else { return nil }
        let heldAssets = pm.per_asset.keys.filter { asset in
            let pa = pm.per_asset[asset]!
            return (pa.units_held + pa.holding_qty) > 0
        }.filter { history[$0] != nil && (history[$0]?.count ?? 0) >= 2 }
        guard heldAssets.count >= 2 else { return nil }
        var commonDates: Set<String>?
        for asset in heldAssets {
            let dates = Set(history[asset]!.keys)
            if commonDates == nil { commonDates = dates }
            else { commonDates = commonDates!.intersection(dates) }
        }
        guard let dates = commonDates, dates.count >= 2 else { return nil }
        let sortedDates = dates.sorted()
        var returnSeries: [String: [Double]] = [:]
        for asset in heldAssets {
            let prices = history[asset]!
            var returns: [Double] = []
            for i in 1..<sortedDates.count {
                let d0 = sortedDates[i - 1], d1 = sortedDates[i]
                guard let p0 = prices[d0], let p1 = prices[d1], p0 > 0 else { continue }
                returns.append((p1 - p0) / p0)
            }
            if returns.count >= 2 { returnSeries[asset] = returns }
        }
        guard returnSeries.count >= 2 else { return nil }
        return metrics.computeCorrelationMatrix(returnSeries: returnSeries)
    }

    func addAlertRule(_ rule: AlertRule) {
        var list = alertRules
        list.append(rule)
        alertRules = list
    }

    func removeAlertRule(id: String) {
        alertRules = alertRules.filter { $0.id != id }
    }

    func updateAlertRule(_ rule: AlertRule) {
        var list = alertRules
        if let idx = list.firstIndex(where: { $0.id == rule.id }) {
            list[idx] = rule
            alertRules = list
        }
    }

    func dismissTriggeredAlerts() {
        triggeredAlerts.removeAll()
    }

    private struct BackupPayload: Codable {
        let exported_at: String
        let users: [String]
        let data_by_user: [String: AppData]
        let price_history: [String: [String: Double]]?
    }

    /// Produces a timestamped JSON backup of all users' data (trades, settings, accounts, account_groups, price history). Returns nil on failure.
    func backupData() -> Data? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let exportedAt = formatter.string(from: Date())
        var dataByUser: [String: AppData] = [:]
        for user in users {
            if let d = try? storage.loadData(username: user) {
                dataByUser[user] = d
            }
        }
        let priceHistory = storage.loadPriceHistory()
        let payload = BackupPayload(exported_at: exportedAt, users: users, data_by_user: dataByUser, price_history: priceHistory)
        return try? JSONEncoder().encode(payload)
    }

    /// Returns the backup file's exported_at timestamp for display (e.g. in restore confirmation). Nil if decode fails.
    func backupExportedAt(data: Data) -> String? {
        (try? JSONDecoder().decode(BackupPayload.self, from: data))?.exported_at
    }

    /// Restores from a backup file (users, data per user, price history). Replaces current storage; then reloads state.
    /// - Returns: nil on success, or an error message string.
    func restoreFromBackup(data: Data) -> String? {
        let payload: BackupPayload
        do {
            payload = try JSONDecoder().decode(BackupPayload.self, from: data)
        } catch {
            return "Invalid backup file: \(error.localizedDescription)"
        }
        guard !payload.users.isEmpty else { return "Backup has no users." }
        for user in payload.users {
            guard let appData = payload.data_by_user[user] else {
                return "Backup missing data for user: \(user)"
            }
            do {
                try storage.saveData(appData, username: user)
            } catch {
                return "Failed to save data for \(user): \(error.localizedDescription)"
            }
        }
        do {
            try storage.saveUsers(payload.users)
        } catch {
            return "Failed to save users: \(error.localizedDescription)"
        }
        storage.savePriceHistory(payload.price_history ?? [:])
        currentUser = payload.users.contains(currentUser) ? currentUser : payload.users[0]
        load()
        return nil
    }

    /// Default filename for backup (timestamped).
    func backupDefaultFilename() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return "fuckyoumoney_backup_\(f.string(from: Date())).json"
    }

    /// Simple query handler for the in-app Assistant: interprets natural-language-style input and returns a formatted answer (no LLM).
    func answerAssistantQuery(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return "Ask something like: portfolio, positions, positions btc, pnl, refresh." }
        if t.contains("refresh") {
            Task { await refreshPrices() }
            return "Refresh started. Prices will update shortly."
        }
        if t.contains("portfolio") || t.contains("total") || t.contains("value") {
            guard let m = portfolioMetrics else { return "No portfolio data. Add trades and refresh." }
            return String(format: "Portfolio: value $%.2f, ROI %.2f%%, realized P&L $%.2f, unrealized P&L $%.2f.",
                          m.total_value, m.roi_pct, m.realized_pnl, m.unrealized_pnl)
        }
        if t.contains("position") {
            let parts = t.split(separator: " ")
            let asset = parts.count > 1 ? String(parts.last!).uppercased() : nil
            let rows = taxLotRows()
            let filtered = asset != nil ? rows.filter { $0.asset == asset } : rows
            if filtered.isEmpty { return asset != nil ? "No position in \(asset!)." : "No positions." }
            let lines = filtered.prefix(10).map { "\($0.asset) \(String(format: "%.4f", $0.qty)) @ $\(String(format: "%.2f", $0.costPerUnit))" }
            return "Positions:\n" + lines.joined(separator: "\n")
        }
        if t.contains("pnl") || t.contains("summary") || t.contains("analytics") {
            guard let m = portfolioMetrics, let a = tradingAnalytics else { return "No analytics. Add trades and refresh." }
            var msg = String(format: "Value $%.2f, ROI %.2f%%, realized $%.2f, unrealized $%.2f. ",
                             m.total_value, m.roi_pct, m.realized_pnl, m.unrealized_pnl)
            msg += String(format: "Max drawdown $%.2f (%.1f%%). ", a.max_drawdown, a.max_drawdown_pct)
            if let s = a.sharpe_ratio { msg += String(format: "Sharpe %.2f. ", s) }
            msg += "Trades: \(a.total_trades) (\(a.winning_trades) W / \(a.losing_trades) L)."
            return msg
        }
        return "Try: portfolio, positions, positions BTC, pnl, refresh."
    }

    /// POSTs a small JSON payload to the configured webhook URL (if set). Fires on trade added and after portfolio refresh.
    private func fireWebhook(event: String, trades: [Trade]?) {
        guard let urlString = webhookURL, let url = URL(string: urlString), url.scheme == "http" || url.scheme == "https" else { return }
        struct WebhookPayload: Encodable {
            let event: String
            let trades: [Trade]?
            let user: String?
        }
        let payload = WebhookPayload(event: event, trades: trades, user: currentUser)
        guard let body = try? JSONEncoder().encode(payload) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 10
        Task.detached(priority: .utility) {
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    func addTradeFromURL(params: [String: String]) {
        guard let asset = params["asset"],
              let type = params["type"],
              let qStr = params["quantity"], let quantity = Double(qStr),
              let pStr = params["price"], let price = Double(pStr) else { return }
        let fee = Double(params["fee"] ?? "0") ?? 0
        let exchange = params["exchange"] ?? "Wallet"
        let accountId = params["account_id"] ?? data.accounts.first?.id
        let totalValue = quantity * price
        let dateStr = params["date"] ?? {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f.string(from: Date())
        }()
        let trade = Trade(
            id: UUID().uuidString,
            date: dateStr,
            asset: asset,
            type: type,
            price: price,
            quantity: quantity,
            exchange: exchange,
            order_type: "",
            fee: fee,
            total_value: totalValue,
            account_id: accountId
        )
        addTrade(trade)
    }

    func addTrade(_ trade: Trade) {
        data.trades.append(trade)
        save()
        recomputeMetrics()
        appendActivity("Added trade: \(trade.asset) \(trade.type) \(trade.quantity)")
        fireWebhook(event: "trade_added", trades: [trade])
    }

    func removeTrade(id: String) {
        data.trades.removeAll { $0.id == id }
        save()
        recomputeMetrics()
    }

    func assignTrade(tradeId: String, accountId: String?) {
        guard let idx = data.trades.firstIndex(where: { $0.id == tradeId }) else { return }
        var t = data.trades[idx]
        t.account_id = accountId
        data.trades[idx] = t
        save()
        recomputeMetrics()
    }

    /// Replace an existing trade by id; used by Edit Trade. Recomputes metrics after.
    func updateTrade(_ trade: Trade) {
        guard let idx = data.trades.firstIndex(where: { $0.id == trade.id }) else { return }
        data.trades[idx] = trade
        save()
        recomputeMetrics()
    }

    /// Realized PnL for a single trade (SELL only), for display in transactions table.
    func realizedPnlForTrade(_ trade: Trade) -> Double? {
        metrics.realizedPnlForTrade(trades: filteredTrades(), tradeId: trade.id, costBasisMethod: data.settings.cost_basis_method)
    }

    /// Profit to show in transactions table: SELL = realized PnL; BUY = (previous_sell_price - buy_price) * qty when applicable.
    func displayProfitForTrade(_ trade: Trade) -> Double? {
        if trade.type == "SELL" {
            return realizedPnlForTrade(trade)
        }
        if trade.type == "BUY" {
            let buyProfits = metrics.buyProfitPerTrade(trades: filteredTrades())
            return buyProfits[trade.id]
        }
        return nil
    }

    func accountName(for accountId: String?) -> String {
        guard let id = accountId, let acc = data.accounts.first(where: { $0.id == id }) else { return "—" }
        return acc.name
    }

    func addAccountGroup(name: String) {
        let id = UUID().uuidString
        let group = AccountGroup(id: id, name: name, accounts: [])
        data.account_groups.append(group)
        save()
    }

    func updateAccountGroup(id: String, name: String) {
        guard let idx = data.account_groups.firstIndex(where: { $0.id == id }) else { return }
        data.account_groups[idx].name = name
        save()
    }

    func addAccount(name: String, groupId: String) {
        let id = UUID().uuidString
        let account = Account(id: id, name: name, account_group_id: groupId, created_date: nil)
        data.accounts.append(account)
        if let gIdx = data.account_groups.firstIndex(where: { $0.id == groupId }) {
            data.account_groups[gIdx].accounts.append(id)
        }
        save()
    }

    func updateAccount(id: String, name: String, groupId: String) {
        guard let accIdx = data.accounts.firstIndex(where: { $0.id == id }) else { return }
        let oldGroupId = data.accounts[accIdx].account_group_id
        let newGroupId = groupId.isEmpty ? nil : groupId
        data.accounts[accIdx].name = name
        data.accounts[accIdx].account_group_id = newGroupId
        if oldGroupId != newGroupId {
            if let old = oldGroupId, let oldIdx = data.account_groups.firstIndex(where: { $0.id == old }) {
                data.account_groups[oldIdx].accounts.removeAll { $0 == id }
            }
            if let new = newGroupId, let newIdx = data.account_groups.firstIndex(where: { $0.id == new }) {
                if !data.account_groups[newIdx].accounts.contains(id) {
                    data.account_groups[newIdx].accounts.append(id)
                }
            }
        }
        save()
    }

    func deleteAccount(id: String) {
        data.accounts.removeAll { $0.id == id }
        for i in data.account_groups.indices {
            data.account_groups[i].accounts.removeAll { $0 == id }
        }
        save()
    }

    /// Reset to default data (clears trades, resets accounts/groups/settings). Call save() and load() after.
    func resetAllData() {
        data = storage.getDefaultData()
        save()
        load()
    }

    func addExchange(name: String, maker: Double, taker: Double) {
        data.settings.fee_structure[name] = MakerTakerFees(maker: maker, taker: taker)
        save()
    }

    func updateExchange(name: String, maker: Double, taker: Double) {
        guard data.settings.fee_structure[name] != nil else { return }
        data.settings.fee_structure[name] = MakerTakerFees(maker: maker, taker: taker)
        save()
    }

    func removeExchange(name: String) {
        data.settings.fee_structure.removeValue(forKey: name)
        if data.settings.default_exchange == name {
            data.settings.default_exchange = data.settings.fee_structure.keys.sorted().first ?? "Wallet"
        }
        save()
    }

    // MARK: - Exchange API keys (Keychain; configured list in Settings)

    /// Saves API key and secret to Keychain and marks the exchange as configured in Settings.
    func saveExchangeAPICredentials(exchange: String, apiKey: String, secret: String) -> Bool {
        guard KeychainService.shared.save(apiKey: apiKey, secret: secret, user: currentUser, exchange: exchange) else { return false }
        if !data.settings.exchange_api_configured.contains(exchange) {
            data.settings.exchange_api_configured.append(exchange)
            data.settings.exchange_api_configured.sort()
            save()
        }
        return true
    }

    /// Removes API credentials from Keychain and from the configured list.
    func removeExchangeAPICredentials(exchange: String) {
        KeychainService.shared.delete(user: currentUser, exchange: exchange)
        data.settings.exchange_api_configured.removeAll { $0 == exchange }
        save()
    }

    /// Returns stored API key and secret for the current user and exchange, or nil.
    func getExchangeAPICredentials(exchange: String) -> (apiKey: String, secret: String)? {
        KeychainService.shared.load(user: currentUser, exchange: exchange)
    }

    /// Whether the exchange has API keys configured for the current user.
    func isExchangeAPIConfigured(_ exchange: String) -> Bool {
        data.settings.exchange_api_configured.contains(exchange)
    }

    /// Refresh balances, fee tier, and 30d volume for the Trading tab. Requires configured API keys.
    func refreshTradingData(exchange: String) async {
        guard let creds = getExchangeAPICredentials(exchange: exchange) else {
            tradingLoadError = "API keys not configured for \(exchange). Add them in Settings."
            tradingBalances = nil
            tradingFeeTier = nil
            tradingVolume30d = nil
            return
        }
        tradingLoadError = nil
        do {
            if exchange == "Kraken" {
                let api = KrakenAPI()
                tradingBalances = try await api.fetchBalances(apiKey: creds.apiKey, secret: creds.secret)
                tradingFeeTier = try await api.fetchFeeTier(apiKey: creds.apiKey, secret: creds.secret)
                tradingVolume30d = try await api.fetch30DayVolume(apiKey: creds.apiKey, secret: creds.secret)
            } else if exchange == "Bitstamp" {
                let api = BitstampAPI()
                tradingBalances = try await api.fetchBalances(apiKey: creds.apiKey, secret: creds.secret)
                tradingFeeTier = try await api.fetchFeeTier(apiKey: creds.apiKey, secret: creds.secret)
                tradingVolume30d = try await api.fetch30DayVolume(apiKey: creds.apiKey, secret: creds.secret)
            } else {
                tradingLoadError = "Unsupported exchange: \(exchange)"
            }
        } catch {
            tradingLoadError = error.localizedDescription
            tradingBalances = nil
            tradingFeeTier = nil
            tradingVolume30d = nil
        }
    }

    /// Place an order on the given exchange. Throws on failure.
    func placeTradingOrder(exchange: String, params: OrderParams) async throws -> OrderResult {
        guard let creds = getExchangeAPICredentials(exchange: exchange) else {
            throw ExchangeAPIError.invalidCredentials
        }
        if exchange == "Kraken" {
            return try await KrakenAPI().placeOrder(apiKey: creds.apiKey, secret: creds.secret, params: params)
        }
        if exchange == "Bitstamp" {
            return try await BitstampAPI().placeOrder(apiKey: creds.apiKey, secret: creds.secret, params: params)
        }
        if exchange == "Binance" || exchange == "Binance Testnet" {
            throw ExchangeAPIError.exchange("Place orders via Crank or the exchange; record fills with POST /v1/trades.")
        }
        throw ExchangeAPIError.exchange("Unsupported exchange: \(exchange)")
    }

    var profitDisplayCurrency: String {
        get { data.settings.profit_display_currency ?? "USD" }
        set { data.settings.profit_display_currency = newValue; save() }
    }

    /// BTC price from cache for profit display in BTC.
    func btcPrice() -> Double? {
        currentPrice(asset: "BTC")
    }

    var projectionsRows: [[String]] {
        get { data.projections ?? [] }
        set { data.projections = newValue.isEmpty ? nil : newValue; save() }
    }

    func addProjectionRow(_ row: [String]) {
        var rows = projectionsRows
        rows.append(row)
        projectionsRows = rows
        appendActivity("Added projection row")
    }

    func updateProjectionRow(at index: Int, _ row: [String]) {
        var rows = projectionsRows
        guard index >= 0, index < rows.count else { return }
        rows[index] = row
        projectionsRows = rows
    }

    func removeProjectionRow(at index: Int) {
        var rows = projectionsRows
        guard index >= 0, index < rows.count else { return }
        rows.remove(at: index)
        projectionsRows = rows
        appendActivity("Removed projection row")
    }

    func startAPIServer() {
        stopAPIServer()
        let port = apiPort > 0 ? apiPort : 38472
        let server = LocalAPIServer(port: UInt16(port)) { [weak self] request in
            await self?.handleAPIRequest(request) ?? .empty(status: 500)
        }
        server.start()
        apiServer = server
    }

    func stopAPIServer() {
        apiServer?.stop()
        apiServer = nil
    }

    /// Loads data for a user and filters trades by optional account_id or group_id. Used by API endpoints.
    private func apiTradesForUser(user: String, accountId: String?, groupId: String?) -> (AppData, [Trade])? {
        guard users.contains(user) else { return nil }
        let dataForUser: AppData
        if user == currentUser { dataForUser = data }
        else { guard let d = try? storage.loadData(username: user) else { return nil }; dataForUser = d }
        var list = dataForUser.trades
        if let aid = accountId, !aid.isEmpty {
            list = list.filter { $0.account_id == aid }
        } else if let gid = groupId, !gid.isEmpty,
                  let group = dataForUser.account_groups.first(where: { $0.id == gid }) {
            let ids = Set(group.accounts)
            list = list.filter { ids.contains($0.account_id ?? "") }
        }
        return (dataForUser, list)
    }

    private func handleAPIRequest(_ request: LocalAPIServer.APIRequest) async -> LocalAPIServer.APIResponse {
        func err(_ msg: String, status: Int) -> LocalAPIServer.APIResponse {
            let body = (try? JSONEncoder().encode(["error": msg])) ?? Data("{\"error\":\"\(msg)\"}".utf8)
            return .json(body, status: status)
        }
        switch (request.method, request.path) {
        case ("GET", "/v1/health"):
            return .json(Data("{}".utf8), status: 200)
        case ("GET", "/v1/portfolio"):
            let user = request.query["user"] ?? currentUser
            guard users.contains(user) else { return err("unknown user", status: 404) }
            let dataForUser: AppData
            if user == currentUser { dataForUser = data }
            else { guard let d = try? storage.loadData(username: user) else { return err("load failed", status: 500) }; dataForUser = d }
            let trades = dataForUser.trades
            func getPrice(_ asset: String) -> Double? {
                if asset.uppercased() == "USDC" || asset.uppercased() == "USDT" { return 1.0 }
                if let entry = priceCache[Self.priceCacheKey(asset: asset)], let p = entry["price"] as? Double { return p }
                return nil
            }
            let m = metrics.computePortfolioMetrics(trades: trades, costBasisMethod: dataForUser.settings.cost_basis_method, getCurrentPrice: getPrice)
            struct PortfolioPayload: Encodable {
                let total_value: Double
                let total_pnl: Double
                let roi_pct: Double
                let realized_pnl: Double
                let unrealized_pnl: Double
            }
            let payload = PortfolioPayload(total_value: m.total_value, total_pnl: m.total_pnl, roi_pct: m.roi_pct, realized_pnl: m.realized_pnl, unrealized_pnl: m.unrealized_pnl)
            if let data = try? JSONEncoder().encode(payload) { return .json(data, status: 200) }
            return err("internal error", status: 500)
        case ("GET", "/v1/positions"):
            let user = request.query["user"] ?? currentUser
            let accountId = request.query["account_id"]
            let groupId = request.query["group_id"]
            guard let (dataForUser, list) = apiTradesForUser(user: user, accountId: accountId, groupId: groupId) else {
                return err(users.contains(user) ? "load failed" : "unknown user", status: users.contains(user) ? 500 : 404)
            }
            func getPrice(_ asset: String) -> Double? {
                if asset.uppercased() == "USDC" || asset.uppercased() == "USDT" { return 1.0 }
                if let entry = priceCache[Self.priceCacheKey(asset: asset)], let p = entry["price"] as? Double { return p }
                return nil
            }
            let m = metrics.computePortfolioMetrics(trades: list, costBasisMethod: dataForUser.settings.cost_basis_method, getCurrentPrice: getPrice)
            struct PositionRow: Encodable {
                let asset: String
                let qty: Double
                let cost_basis: Double
                let current_value: Double
                let unrealized_pnl: Double
                let realized_pnl: Double
            }
            let positions = m.per_asset.map { PositionRow(asset: $0.key, qty: $0.value.units_held + $0.value.holding_qty, cost_basis: $0.value.cost_basis, current_value: $0.value.current_value, unrealized_pnl: $0.value.unrealized_pnl, realized_pnl: $0.value.realized_pnl) }
            if let data = try? JSONEncoder().encode(positions) { return .json(data, status: 200) }
            return err("internal error", status: 500)
        case ("GET", "/v1/trades"):
            let user = request.query["user"] ?? currentUser
            let accountId = request.query["account_id"]
            let groupId = request.query["group_id"]
            guard let (_, list) = apiTradesForUser(user: user, accountId: accountId, groupId: groupId) else {
                return err(users.contains(user) ? "load failed" : "unknown user", status: users.contains(user) ? 500 : 404)
            }
            var filtered = list
            if let asset = request.query["asset"], !asset.isEmpty {
                filtered = filtered.filter { $0.asset == asset }
            }
            if let since = request.query["since"], !since.isEmpty {
                filtered = filtered.filter { $0.date >= since }
            }
            filtered.sort { $0.date > $1.date }
            if let limitStr = request.query["limit"], let limit = Int(limitStr), limit > 0 {
                filtered = Array(filtered.prefix(limit))
            }
            if let data = try? JSONEncoder().encode(filtered) { return .json(data, status: 200) }
            return err("internal error", status: 500)
        case ("GET", "/v1/analytics/summary"):
            let user = request.query["user"] ?? currentUser
            guard let (dataForUser, list) = apiTradesForUser(user: user, accountId: nil, groupId: nil) else {
                return err(users.contains(user) ? "load failed" : "unknown user", status: users.contains(user) ? 500 : 404)
            }
            func getPrice(_ asset: String) -> Double? {
                if asset.uppercased() == "USDC" || asset.uppercased() == "USDT" { return 1.0 }
                if let entry = priceCache[Self.priceCacheKey(asset: asset)], let p = entry["price"] as? Double { return p }
                return nil
            }
            let pm = metrics.computePortfolioMetrics(trades: list, costBasisMethod: dataForUser.settings.cost_basis_method, getCurrentPrice: getPrice)
            let ta = metrics.computeTradingAnalytics(trades: list, costBasisMethod: dataForUser.settings.cost_basis_method, currentTotalValue: pm.total_value)
            struct AnalyticsSummary: Encodable {
                let total_value: Double
                let roi_pct: Double
                let realized_pnl: Double
                let unrealized_pnl: Double
                let max_drawdown: Double
                let max_drawdown_pct: Double
                let sharpe_ratio: Double?
                let sortino_ratio: Double?
                let realized_volatility: Double?
                let win_rate_pct: Double?
                let total_trades: Int
                let winning_trades: Int
                let losing_trades: Int
            }
            let summary = AnalyticsSummary(total_value: pm.total_value, roi_pct: pm.roi_pct, realized_pnl: pm.realized_pnl, unrealized_pnl: pm.unrealized_pnl, max_drawdown: ta.max_drawdown, max_drawdown_pct: ta.max_drawdown_pct, sharpe_ratio: ta.sharpe_ratio, sortino_ratio: ta.sortino_ratio, realized_volatility: ta.realized_volatility, win_rate_pct: ta.win_rate_pct, total_trades: ta.total_trades, winning_trades: ta.winning_trades, losing_trades: ta.losing_trades)
            if let data = try? JSONEncoder().encode(summary) { return .json(data, status: 200) }
            return err("internal error", status: 500)
        case ("GET", "/v1/analytics/correlation"):
            struct CorrelationResponse: Encodable {
                let message: String
                let assets: [String]
                let matrix: [[Double]]
            }
            if let matrix = correlationMatrixSync() {
                let response = CorrelationResponse(message: "Pairwise Pearson correlation of daily returns (from stored price history).", assets: matrix.assets, matrix: matrix.matrix)
                if let data = try? JSONEncoder().encode(response) { return .json(data, status: 200) }
            } else {
                let stub = CorrelationResponse(message: "Insufficient price history: refresh prices on at least 2 days for 2+ held assets to see the correlation matrix.", assets: [], matrix: [])
                if let data = try? JSONEncoder().encode(stub) { return .json(data, status: 200) }
            }
            return err("internal error", status: 500)
        case ("GET", "/v1/docs"):
            if let data = Self.apiDocsMarkdown.data(using: .utf8) {
                return LocalAPIServer.APIResponse(statusCode: 200, body: data, contentType: "text/markdown")
            }
            return err("docs unavailable", status: 500)
        case ("GET", "/v1/query"):
            let user = request.query["user"] ?? currentUser
            let q = request.query["q"] ?? ""
            guard users.contains(user) else { return err("unknown user", status: 404) }
            guard let (dataForUser, list) = apiTradesForUser(user: user, accountId: request.query["account_id"], groupId: request.query["group_id"]) else {
                return err("load failed", status: 500)
            }
            func getPrice(_ asset: String) -> Double? {
                if asset.uppercased() == "USDC" || asset.uppercased() == "USDT" { return 1.0 }
                if let entry = priceCache[Self.priceCacheKey(asset: asset)], let p = entry["price"] as? Double { return p }
                return nil
            }
            switch q.lowercased() {
            case "portfolio":
                let m = metrics.computePortfolioMetrics(trades: list, costBasisMethod: dataForUser.settings.cost_basis_method, getCurrentPrice: getPrice)
                struct Q: Encodable { let total_value: Double; let total_pnl: Double; let roi_pct: Double; let realized_pnl: Double; let unrealized_pnl: Double }
                let payload = Q(total_value: m.total_value, total_pnl: m.total_pnl, roi_pct: m.roi_pct, realized_pnl: m.realized_pnl, unrealized_pnl: m.unrealized_pnl)
                if let data = try? JSONEncoder().encode(payload) { return .json(data, status: 200) }
            case "positions":
                let m = metrics.computePortfolioMetrics(trades: list, costBasisMethod: dataForUser.settings.cost_basis_method, getCurrentPrice: getPrice)
                struct Pos: Encodable { let asset: String; let qty: Double; let cost_basis: Double; let current_value: Double; let unrealized_pnl: Double; let realized_pnl: Double }
                var positions = m.per_asset.map { Pos(asset: $0.key, qty: $0.value.units_held + $0.value.holding_qty, cost_basis: $0.value.cost_basis, current_value: $0.value.current_value, unrealized_pnl: $0.value.unrealized_pnl, realized_pnl: $0.value.realized_pnl) }
                if let asset = request.query["asset"], !asset.isEmpty { positions = positions.filter { $0.asset == asset } }
                if let data = try? JSONEncoder().encode(positions) { return .json(data, status: 200) }
            case "pnl_summary":
                let m = metrics.computePortfolioMetrics(trades: list, costBasisMethod: dataForUser.settings.cost_basis_method, getCurrentPrice: getPrice)
                let period = request.query["period"] ?? ""
                var realizedInPeriod: Double? = nil
                if period == "7d" || period == "30d" {
                    let days = period == "7d" ? 7 : 30
                    let cal = Calendar.current
                    guard let since = cal.date(byAdding: .day, value: -days, to: Date()) else { break }
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let sinceStr = formatter.string(from: since)
                    let sellsInPeriod = list.filter { $0.type == "SELL" && $0.date >= sinceStr }
                    realizedInPeriod = sellsInPeriod.compactMap { metrics.realizedPnlForTrade(trades: list, tradeId: $0.id, costBasisMethod: dataForUser.settings.cost_basis_method) }.reduce(0, +)
                }
                struct PnlSum: Encodable { let total_value: Double; let realized_pnl: Double; let unrealized_pnl: Double; let realized_pnl_period: Double? }
                let payload = PnlSum(total_value: m.total_value, realized_pnl: m.realized_pnl, unrealized_pnl: m.unrealized_pnl, realized_pnl_period: realizedInPeriod)
                if let data = try? JSONEncoder().encode(payload) { return .json(data, status: 200) }
            default:
                return err("unknown query: use q=portfolio|positions|pnl_summary", status: 400)
            }
            return err("internal error", status: 500)
        case ("POST", "/v1/command"):
            guard let body = request.body,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let intent = json["intent"] as? String else {
                return err("invalid JSON or missing intent", status: 400)
            }
            let params = (json["params"] as? [String: Any]) ?? [:]
            switch intent {
            case "refresh_prices":
                await refreshPrices()
                struct CommandRefreshResponse: Encodable { let success: Bool; let message: String }
                if let data = try? JSONEncoder().encode(CommandRefreshResponse(success: true, message: "refresh started")) { return .json(data, status: 200) }
            case "add_trade":
                guard let asset = params["asset"] as? String, let type = params["type"] as? String,
                      let q = params["quantity"] as? Double, let p = params["price"] as? Double else {
                    return err("add_trade requires params: asset, type, quantity, price", status: 400)
                }
                let defaultAccountId = await MainActor.run { data.accounts.first?.id }
                let trade = Trade(
                    id: UUID().uuidString,
                    date: (params["date"] as? String) ?? isoNow(),
                    asset: asset,
                    type: type,
                    price: p,
                    quantity: q,
                    exchange: (params["exchange"] as? String) ?? "Wallet",
                    order_type: (params["order_type"] as? String) ?? "",
                    fee: (params["fee"] as? Double) ?? 0,
                    total_value: q * p,
                    account_id: (params["account_id"] as? String) ?? defaultAccountId,
                    source: params["source"] as? String,
                    strategy_id: params["strategy_id"] as? String
                )
                await MainActor.run { addTrade(trade) }
                struct CommandTradeResponse: Encodable { let success: Bool; let trade: Trade }
                if let data = try? JSONEncoder().encode(CommandTradeResponse(success: true, trade: trade)) { return .json(data, status: 201) }
            default:
                return err("unknown intent: use refresh_prices or add_trade", status: 400)
            }
            return err("internal error", status: 500)
        case ("POST", "/v1/trades"):
            guard let body = request.body,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return err("invalid JSON or body", status: 400) }
            var added: [Trade] = []
            if let single = json["asset"] as? String, let type = json["type"] as? String, let q = json["quantity"] as? Double, let p = json["price"] as? Double {
                let defaultAccountId = await MainActor.run { data.accounts.first?.id }
                let trade = Trade(id: UUID().uuidString, date: (json["date"] as? String) ?? isoNow(), asset: single, type: type, price: p, quantity: q, exchange: (json["exchange"] as? String) ?? "Wallet", order_type: (json["order_type"] as? String) ?? "", fee: (json["fee"] as? Double) ?? 0, total_value: q * p, account_id: (json["account_id"] as? String) ?? defaultAccountId, source: json["source"] as? String, strategy_id: json["strategy_id"] as? String)
                await MainActor.run { addTrade(trade); added.append(trade) }
            } else if let arr = json["trades"] as? [[String: Any]] {
                let decoder = JSONDecoder()
                for t in arr {
                    if let td = try? JSONSerialization.data(withJSONObject: t), var trade = try? decoder.decode(Trade.self, from: td) {
                        if trade.id.isEmpty { trade.id = UUID().uuidString }
                        await MainActor.run { addTrade(trade); added.append(trade) }
                    }
                }
            }
            if let data = try? JSONEncoder().encode(added) { return .json(data, status: 201) }
            return .json(Data("[]".utf8), status: 201)
        case ("POST", "/v1/refresh"):
            await refreshPrices()
            return .empty(status: 202)
        default:
            return err("Not found", status: 404)
        }
    }

    /// API documentation served at GET /v1/docs (Markdown).
    private static let apiDocsMarkdown = """
    # FuckYouMoney Local API (v1)

    Base URL: http://localhost:<port> (port in Settings; default 38472).

    ## Endpoints

    ### GET /v1/health
    Returns `{}`. Liveness check.

    ### GET /v1/portfolio
    Query: `user` (optional). Returns total_value, total_pnl, roi_pct, realized_pnl, unrealized_pnl.

    ### GET /v1/positions
    Query: `user`, `account_id`, `group_id` (all optional). Returns array of { asset, qty, cost_basis, current_value, unrealized_pnl, realized_pnl }.

    ### GET /v1/trades
    Query: `user`, `account_id`, `group_id`, `asset`, `since`, `limit` (all optional). Returns array of trades (newest first).

    ### POST /v1/trades
    Body: single { asset, type, quantity, price, exchange?, order_type?, fee?, date?, account_id? } or { trades: [ ... ] }. Returns created trades.

    ### GET /v1/analytics/summary
    Query: `user` (optional). Returns total_value, roi_pct, realized_pnl, unrealized_pnl, max_drawdown, max_drawdown_pct, sharpe_ratio, sortino_ratio, win_rate_pct, total_trades, winning_trades, losing_trades.

    ### GET /v1/analytics/correlation
    Query: `user` (optional). Returns { "message", "assets", "matrix" }. When per-asset return series are not yet available, returns empty assets/matrix and a message. When implemented, returns pairwise correlation matrix for held assets.

    ### POST /v1/refresh
    Triggers price refresh. Returns 202 Accepted.

    ### GET /v1/docs
    This documentation (text/markdown).

    ### GET /v1/query (AI-friendly)
    Query: `q`=portfolio|positions|pnl_summary; optional `user`, `account_id`, `group_id`, `asset` (for positions), `period` (for pnl_summary: 7d|30d). Returns JSON for the named query.

    ### POST /v1/command (AI-friendly)
    Body: { "intent": "refresh_prices" } or { "intent": "add_trade", "params": { "asset", "type", "quantity", "price", ... } }. Returns { "success": true } or { "success": true, "trade": { ... } }.

    Errors: 4xx/5xx body is JSON: { "error": "message" }.
    """
}

private func isoNow() -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: Date())
}
