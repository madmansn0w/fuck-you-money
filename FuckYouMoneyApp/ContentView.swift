import SwiftUI
import AppKit
import UserNotifications
import FuckYouMoneyCore
import Charts

// MARK: - Animated number (slot-machine style, 1s)

/// Displays a number with a 1-second slot-machine style animation when the value changes (e.g. after price refresh).
enum AnimatedNumberFormat {
    case currency
    case currencyBtc  // value in BTC, shows "X.XXXXXXXX BTC"
    case percent
    case percent1  // one decimal, e.g. 12.3%
    case percentSigned
    case plain(Int)  // decimal places
}

struct AnimatedNumberText: View {
    let value: Double
    let format: AnimatedNumberFormat
    var color: Color? = nil
    var font: Font = .body

    private var formatted: String {
        switch format {
        case .currency: return String(format: "$%.2f", value)
        case .currencyBtc: return String(format: "%.8f BTC", value)
        case .percent: return String(format: "%.2f%%", value)
        case .percent1: return String(format: "%.1f%%", value)
        case .percentSigned: return String(format: "%+.2f%%", value)
        case .plain(let d):
            return String(format: "%.\(d)f", value)
        }
    }

    var body: some View {
        Text(formatted)
            .font(font)
            .foregroundColor(color ?? .primary)
            .modifier(SlotMachineModifier(value: value))
    }
}

/// Slot-machine style number animation (1 second) when value changes. Uses numericText on macOS 14+.
private struct SlotMachineModifier: ViewModifier {
    let value: Double
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .contentTransition(.numericText(value: value))
                .animation(.easeInOut(duration: 1), value: value)
        } else {
            content
                .contentTransition(.numericText(countsDown: false))
                .animation(.easeInOut(duration: 1), value: value)
        }
    }
}

// MARK: - Main content (3-pane: Sidebar | Summary | Content tabs)

/// Tab identifiers for the main content area; order is persisted and user-configurable.
private let tabIds = ["dashboard", "trading", "transactions", "charts", "assets", "assistant", "polymarket"]
private let defaultTabOrderKey = "dashboard,trading,transactions,charts,assets,assistant,polymarket"

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("tabOrder") private var tabOrderRaw = defaultTabOrderKey
    @State private var selectedTabId: String = "dashboard"
    @State private var showSettings = false
    @State private var showAddUser = false
    @State private var showSwitchUser = false
    @State private var showManageUsers = false
    @State private var showNewAccount = false
    @State private var showManageAccounts = false
    @State private var showAbout = false
    @State private var showExport = false
    @State private var showImport = false
    @State private var showAddGroup = false
    @State private var groupToEdit: AccountGroup?
    @State private var accountToEdit: Account?

    /// Persisted tab order; invalid or missing ids are appended so we always have four tabs.
    private var tabOrder: [String] {
        let parsed = tabOrderRaw.split(separator: ",").map(String.init)
        let valid = parsed.filter { tabIds.contains($0) }
        let missing = tabIds.filter { !valid.contains($0) }
        return valid + missing
    }

    private func tabLabel(_ id: String) -> String {
        switch id {
        case "dashboard": return "Dashboard"
        case "trading": return "Trading"
        case "transactions": return "Transactions"
        case "charts": return "Charts"
        case "assets": return "Assets"
        case "assistant": return "Assistant"
        case "polymarket": return "Polymarket"
        default: return id
        }
    }

    @ViewBuilder
    private func tabContent(for id: String) -> some View {
        switch id {
        case "dashboard": DashboardTabView()
        case "trading": TradingTabView(showSettings: { showSettings = true })
        case "transactions": TransactionsTabView()
        case "charts": PnLChartTabView()
        case "assistant": AssistantTabView()
        case "polymarket": PolymarketTabView()
        default: DashboardTabView()
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(onEditGroup: { groupToEdit = $0 }, onEditAccount: { accountToEdit = $0 })
        } content: {
            SummaryPanelView()
        } detail: {
            VStack(spacing: 0) {
                if let msg = appState.errorMessage {
                    HStack {
                        Text(msg).font(.caption).foregroundColor(.red).lineLimit(2)
                        Spacer()
                        Button("Dismiss") { appState.errorMessage = nil }
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                }
                Picker("", selection: $selectedTabId) {
                    ForEach(tabOrder, id: \.self) { id in
                        Text(tabLabel(id)).tag(id)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                tabContent(for: selectedTabId)
            }
        }
        .onChange(of: appState.pendingAddTradeAsset) { _, newValue in
            if newValue != nil { selectedTabId = "transactions" }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Refresh prices") { Task { await appState.refreshPrices() } }
                    Button("Add user…") { showAddUser = true }
                    Button("Switch user…") { showSwitchUser = true }
                    Button("Manage users…") { showManageUsers = true }
                    Divider()
                    Button("Add portfolio…") { showAddGroup = true }
                    Button("New account…") { showNewAccount = true }
                    Button("Manage accounts…") { showManageAccounts = true }
                    Divider()
                    Button("Export trades…") { showExport = true }
                    Button("Import trades…") { showImport = true }
                    Divider()
                    Button("Settings…") { showSettings = true }
                    Button("About") { showAbout = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear {
            appState.load()
            if appState.apiEnabled { appState.startAPIServer() }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showAddUser) { AddUserSheet(onDismiss: { showAddUser = false }) }
        .sheet(isPresented: $showSwitchUser) { SwitchUserSheet(onDismiss: { showSwitchUser = false }) }
        .sheet(isPresented: $showManageUsers) { ManageUsersSheet(onDismiss: { showManageUsers = false }) }
        .sheet(isPresented: $showNewAccount) { NewAccountSheet(onDismiss: { showNewAccount = false }) }
        .sheet(isPresented: $showManageAccounts) { ManageAccountsSheet(onDismiss: { showManageAccounts = false }) }
        .sheet(isPresented: $showAbout) { AboutSheet(onDismiss: { showAbout = false }) }
        .sheet(isPresented: $showExport) { ExportSheet(onDismiss: { showExport = false }) }
        .sheet(isPresented: $showImport) { ImportSheet(onDismiss: { showImport = false }) }
        .sheet(isPresented: $showAddGroup) { AddGroupSheet(onDismiss: { showAddGroup = false }, onAdd: { name in
            appState.addAccountGroup(name: name)
            showAddGroup = false
        }) }
        .sheet(item: $groupToEdit) { group in
            EditGroupSheet(group: group, onDismiss: { groupToEdit = nil }, onSave: { name in
                appState.updateAccountGroup(id: group.id, name: name)
                groupToEdit = nil
            })
        }
        .sheet(item: $accountToEdit) { acc in
            EditAccountSheet(account: acc, onDismiss: { accountToEdit = nil }, onSave: { name, groupId in
                appState.updateAccount(id: acc.id, name: name, groupId: groupId)
                accountToEdit = nil
            })
        }
    }
}

// MARK: - Sidebar (account groups + accounts)

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    var onEditGroup: (AccountGroup) -> Void
    var onEditAccount: (Account) -> Void

    private var isAllSelected: Bool {
        appState.selectedGroupId == nil && appState.selectedAccountId == nil
    }

    var body: some View {
        List {
            Section("All") {
                Button("All accounts") {
                    appState.selectedGroupId = nil
                    appState.selectedAccountId = nil
                    appState.recomputeMetrics()
                }
                .buttonStyle(.plain)
                .listRowBackground(isAllSelected ? Color.accentColor.opacity(0.15) : nil)
            }
            ForEach(appState.data.account_groups) { group in
                Section {
                    ForEach(accountsInGroup(group)) { account in
                        Button(account.name) {
                            appState.selectedGroupId = nil
                            appState.selectedAccountId = account.id
                            appState.recomputeMetrics()
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(appState.selectedAccountId == account.id ? Color.accentColor.opacity(0.15) : nil)
                        .contextMenu {
                            Button("Edit account…") { onEditAccount(account) }
                        }
                    }
                } header: {
                    HStack {
                        Text(group.name)
                        Spacer()
                    }
                    .contextMenu {
                        Button("Edit group…") { onEditGroup(group) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button(appState.profitDisplayCurrency == "BTC" ? "Profit in BTC" : "Profit in USD") {
                appState.profitDisplayCurrency = appState.profitDisplayCurrency == "USD" ? "BTC" : "USD"
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private func accountsInGroup(_ group: AccountGroup) -> [Account] {
        let ids = Set(group.accounts)
        return appState.data.accounts.filter { ids.contains($0.id) }
    }
}

// MARK: - Summary panel (scope, asset filter, metrics, per-asset cards)

struct SummaryPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var assetFilter: String = "All"

    private var scopeLabel: String {
        if let aid = appState.selectedAccountId,
           let acc = appState.data.accounts.first(where: { $0.id == aid }) {
            return acc.name
        }
        if let gid = appState.selectedGroupId,
           let grp = appState.data.account_groups.first(where: { $0.id == gid }) {
            return grp.name
        }
        return "All accounts"
    }

    private var filteredPerAsset: [String: PerAssetMetrics] {
        guard let m = appState.portfolioMetrics else { return [:] }
        if assetFilter == "All" { return m.per_asset }
        return m.per_asset.filter { $0.key == assetFilter }
    }

    /// Sorted asset symbols for the asset filter picker (avoids complex expression in body for compiler).
    private var sortedAssetKeys: [String] {
        guard let keys = appState.portfolioMetrics?.per_asset.keys else { return [] }
        return keys.sorted()
    }

    /// Assets with holding > 0 (open positions).
    private var openPositions: [String: PerAssetMetrics] {
        guard let m = appState.portfolioMetrics else { return [:] }
        return m.per_asset.filter { $0.value.holding_qty + $0.value.units_held > 0 }
    }

    /// Assets with zero holding and non-zero lifetime P&L (closed positions).
    private var closedPositions: [String: PerAssetMetrics] {
        guard let m = appState.portfolioMetrics else { return [:] }
        return m.per_asset.filter { ($0.value.holding_qty + $0.value.units_held) == 0 && $0.value.lifetime_pnl != 0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(scopeLabel).font(.headline)
                Picker("Asset", selection: $assetFilter) {
                    Text("All").tag("All")
                    ForEach(sortedAssetKeys, id: \.self) { key in
                        Text(key).tag(key)
                    }
                }
                .pickerStyle(.menu)
                if let m = appState.portfolioMetrics {
                    VStack(alignment: .leading, spacing: 6) {
                        summaryRow("Portfolio value", value: m.total_value, format: .currency, tooltip: "Total current value of portfolio including USD balance.")
                        summaryRow("Capital in", value: m.total_external_cash, format: .currency, tooltip: "Total USD deposited minus withdrawals.")
                        summaryRow("Total P&L", value: m.total_pnl, format: .currency, colorize: true, tooltip: "Realized plus unrealized P&L.")
                        summaryRow("ROI", value: m.roi_pct, format: .percent, colorize: true, tooltip: "Return on capital in.")
                        summaryRow("Realized P&L", value: m.realized_pnl, format: .currency, colorize: true, tooltip: "P&L from closed positions.")
                        summaryRow("Unrealized P&L", value: m.unrealized_pnl, format: .currency, colorize: true, tooltip: "P&L on current holdings.")
                        if let roiCost = m.roi_on_cost_pct {
                            summaryRow("ROI (on cost)", value: roiCost, format: .percent, colorize: true, tooltip: "Return on cost basis.")
                        }
                        if let p24 = appState.portfolio24hUsd() {
                            summaryRow("Portfolio 24h", value: p24, format: .currency, colorize: true, tooltip: "USD change in portfolio value over last 24h.")
                        }
                    }
                    if let a = appState.tradingAnalytics {
                        Divider()
                        Text("Trading analytics").font(.subheadline)
                        summaryRow("Max drawdown", value: a.max_drawdown, format: .currency, tooltip: "Largest peak-to-trough decline in portfolio value.")
                        summaryRow("Max drawdown %", value: a.max_drawdown_pct, format: .percent, tooltip: "Max drawdown as % of peak value.")
                        if let sharpe = a.sharpe_ratio {
                            summaryRow("Sharpe ratio", value: sharpe, format: .plain(2), tooltip: "Risk-adjusted return (mean return / std deviation).")
                        }
                        if let sortino = a.sortino_ratio {
                            summaryRow("Sortino ratio", value: sortino, format: .plain(2), tooltip: "Risk-adjusted return using downside deviation only.")
                        }
                        if let wr = a.win_rate_pct {
                            summaryRow("Win rate", value: wr, format: .percent1, tooltip: "Percentage of trades with profit > 0.")
                        }
                        summaryRow("Trades", value: Double(a.total_trades), format: .plain(0), tooltip: "\(a.winning_trades) wins, \(a.losing_trades) losses")
                    }
                    Divider()
                    Text("Accounts").font(.subheadline)
                    ForEach(appState.perAccountMetricsInScope(), id: \.accountId) { row in
                        HStack {
                            Text(row.accountName).font(.caption)
                            Spacer()
                            AnimatedNumberText(value: row.value, format: .currency, font: .caption)
                            AnimatedNumberText(value: row.pnl, format: .currency, color: row.pnl >= 0 ? .green : .red, font: .caption)
                        }
                        .padding(.vertical, 2)
                    }
                    Divider()
                    Text("Per asset").font(.subheadline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(Array(filteredPerAsset.keys.sorted()), id: \.self) { asset in
                            if let pa = filteredPerAsset[asset] {
                                perAssetCard(asset: asset, pa: pa, pct24h: appState.pctChange24h(asset: asset))
                            }
                        }
                    }
                    Divider()
                    Text("Open Positions").font(.subheadline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(Array(openPositions.keys.sorted()), id: \.self) { asset in
                            if let pa = openPositions[asset] {
                                openPositionCard(asset: asset, pa: pa)
                            }
                        }
                    }
                    if !closedPositions.isEmpty {
                        Divider()
                        Text("Closed Positions").font(.subheadline)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(Array(closedPositions.keys.sorted()), id: \.self) { asset in
                                if let pa = closedPositions[asset] {
                                    closedPositionCard(asset: asset, pa: pa)
                                }
                            }
                        }
                    }
                } else {
                    Text("No metrics")
                }
            }
            .padding()
        }
        .frame(minWidth: 280, maxWidth: 400)
    }

    private enum ValueFormat { case currency; case percent; case percent1; case plain(Int) }
    private func summaryRow(_ label: String, value: Double, format: ValueFormat, colorize: Bool = false, tooltip: String? = nil) -> some View {
        let color: Color? = colorize ? (value >= 0 ? .green : .red) : nil
        let animFormat: AnimatedNumberFormat = {
            switch format {
            case .currency: return .currency
            case .percent: return .percent
            case .percent1: return .percent1
            case .plain(let d): return .plain(d)
            }
        }()
        return HStack {
            Text(label).font(.caption).foregroundColor(.secondary)
                .help(tooltip ?? label)
            Spacer()
            AnimatedNumberText(value: value, format: animFormat, color: color, font: .subheadline.weight(.medium))
        }
    }

    private func perAssetCard(asset: String, pa: PerAssetMetrics, pct24h: Double?) -> some View {
        let qty = pa.holding_qty + pa.units_held
        let isClosed = qty == 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(asset).font(.subheadline).fontWeight(.semibold)
                if isClosed { Text("|closed)").font(.caption).foregroundColor(.secondary) }
            }
            HStack {
                Text("Qty:").font(.caption).foregroundColor(.secondary)
                AnimatedNumberText(value: qty, format: .plain(4), font: .caption)
            }
            HStack {
                Text("Value:").font(.caption).foregroundColor(.secondary)
                AnimatedNumberText(value: pa.current_value, format: .currency, font: .caption)
            }
            HStack {
                Text("P&L:").font(.caption).foregroundColor(.secondary)
                AnimatedNumberText(value: pa.lifetime_pnl, format: .currency, color: pa.lifetime_pnl >= 0 ? .green : .red, font: .caption)
            }
            if let pct = pct24h {
                HStack {
                    Text("24h:").font(.caption).foregroundColor(.secondary)
                    AnimatedNumberText(value: pct, format: .percentSigned, color: pct >= 0 ? .green : .red, font: .caption)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private func openPositionCard(asset: String, pa: PerAssetMetrics) -> some View {
        let qty = pa.holding_qty + pa.units_held
        let entryPrice = qty > 0 ? pa.cost_basis / qty : 0.0
        return VStack(alignment: .leading, spacing: 4) {
            Text(asset).font(.caption).fontWeight(.semibold)
            HStack {
                Text("Entry:").font(.caption).foregroundColor(.secondary)
                AnimatedNumberText(value: entryPrice, format: .currency, font: .caption)
            }
            HStack {
                Text("Value:").font(.caption).foregroundColor(.secondary)
                AnimatedNumberText(value: pa.current_value, format: .currency, font: .caption)
            }
            HStack {
                Text("Profit:").font(.caption).foregroundColor(.secondary)
                AnimatedNumberText(value: pa.unrealized_pnl, format: .currency, color: pa.unrealized_pnl >= 0 ? .green : .red, font: .caption)
            }
            HStack {
                Text("Qty:").font(.caption).foregroundColor(.secondary)
                AnimatedNumberText(value: qty, format: .plain(4), font: .caption)
            }
        }
        .padding(6)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }

    private func closedPositionCard(asset: String, pa: PerAssetMetrics) -> some View {
        HStack {
            Text(asset).font(.caption).fontWeight(.medium)
            Spacer()
            AnimatedNumberText(value: pa.lifetime_pnl, format: .currency, color: pa.lifetime_pnl >= 0 ? .green : .red, font: .caption)
        }
        .padding(4)
    }
}

// MARK: - Transactions tab (form + list)

struct TransactionsTabView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("FuckYouMoney.watchlistAssets") private var watchlistRaw = ""
    @State private var asset = "BTC"
    @State private var type = "BUY"
    @State private var quantity = ""
    @State private var price = ""
    @State private var exchange = "Bitstamp"
    @State private var orderType = "Market"
    @State private var orderPostOnly = false
    @State private var orderGTC = false
    @State private var orderGTD = false
    @State private var selectedAccountId: String = ""
    @State private var isSidecarTrade = false
    @State private var sidecarClientName: String = ""
    @State private var tradeToEdit: Trade?
    @State private var sortKey: String = "Date"
    @State private var sortAscending = false

    /// Defaults plus assets from portfolio and watchlist (and pending add-trade) so Add trade from Assets works.
    private var allAssetOptions: [String] {
        let defaults = ["BTC", "ETH", "BNB", "DENT", "USDC", "USDT", "USD"]
        let fromMetrics = Set(appState.portfolioMetrics?.per_asset.keys ?? [])
        let fromWatch = Set(
            watchlistRaw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
                .filter { !$0.isEmpty }
        )
        var opts = Set(defaults)
        opts.formUnion(fromMetrics)
        opts.formUnion(fromWatch)
        if let p = appState.pendingAddTradeAsset, !p.isEmpty { opts.insert(p) }
        return opts.sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("New Trade").font(.headline)
                HStack {
                    Picker("Asset", selection: $asset) {
                        ForEach(allAssetOptions, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Type", selection: $type) {
                        ForEach(["BUY", "SELL", "Transfer", "Deposit", "Withdrawal"], id: \.self) { Text($0).tag($0) }
                    }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Quantity", text: $quantity)
                        HStack(spacing: 6) {
                            quickAddPercentRow(
                                label: "Qty",
                                fill: { pct in
                                    let holding = appState.holdingQty(asset: asset, accountId: selectedAccountId.isEmpty ? nil : selectedAccountId)
                                    quantity = formatDecimal((Double(pct) / 100.0) * holding)
                                }
                            )
                            if type == "BUY" && asset != "USD" && asset != "USDC" && asset != "USDT", let p = Double(price), p > 0 {
                                Button("Max") {
                                    let available = appState.availableUsdcUsd(accountId: selectedAccountId.isEmpty ? nil : selectedAccountId)
                                    quantity = formatDecimal(available / p)
                                }.buttonStyle(.borderless).font(.caption2)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Price", text: $price)
                        quickAddPercentRow(
                            label: "Price",
                            fill: { pct in
                                guard let market = appState.currentPrice(asset: asset), market > 0 else { return }
                                price = formatDecimal((Double(pct) / 100.0) * market)
                            }
                        )
                    }
                }
                Picker("Exchange", selection: $exchange) {
                    ForEach(Array(appState.data.settings.fee_structure.keys.sorted()), id: \.self) { Text($0).tag($0) }
                }
                Picker("Order type", selection: $orderType) {
                    Text("Market").tag("Market")
                    Text("Limit").tag("Limit")
                }
                HStack(spacing: 16) {
                    Toggle("Post-only", isOn: $orderPostOnly).toggleStyle(.checkbox)
                    Toggle("GTC", isOn: $orderGTC).toggleStyle(.checkbox)
                    Toggle("GTD", isOn: $orderGTD).toggleStyle(.checkbox)
                }
                .disabled(orderType != "Limit")
                Picker("Account", selection: $selectedAccountId) {
                    Text("(Default)").tag("")
                    ForEach(appState.data.accounts, id: \.id) { Text($0.name).tag($0.id) }
                }
                .onAppear { if selectedAccountId.isEmpty, let first = appState.data.accounts.first?.id { selectedAccountId = first } }
                Toggle("Sidecar Trade", isOn: $isSidecarTrade)
                if isSidecarTrade {
                    Picker("Sidecar client", selection: $sidecarClientName) {
                        Text("(None)").tag("")
                        ForEach(appState.users.filter { $0 != appState.currentUser }, id: \.self) { Text($0).tag($0) }
                    }
                }
                Button("Add Trade") { addTrade() }
                    .buttonStyle(.borderedProminent)
                Divider()
                HStack {
                    Text("Trades (\(appState.filteredTrades().count))").font(.headline)
                    Menu("Sort") {
                        ForEach(["Date", "Asset", "Type", "Total"], id: \.self) { key in
                            Button(key) { setSort(key) }
                        }
                    }
                }
                transactionTableHeader
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sortedTrades) { trade in
                        transactionRow(trade)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Edit Trade") { tradeToEdit = trade }
                                Button("Delete", role: .destructive) { appState.removeTrade(id: trade.id) }
                                Menu("Assign to account") {
                                    ForEach(appState.data.accounts, id: \.id) { acc in
                                        Button(acc.name) { appState.assignTrade(tradeId: trade.id, accountId: acc.id) }
                                    }
                                    Button("(No account)") { appState.assignTrade(tradeId: trade.id, accountId: nil) }
                                }
                            }
                            .onTapGesture(count: 2) { tradeToEdit = trade }
                    }
                }
            }
            .padding()
        }
        .onAppear {
            if let a = appState.pendingAddTradeAsset, !a.isEmpty {
                asset = a
                appState.pendingAddTradeAsset = nil
            }
        }
        .onChange(of: appState.pendingAddTradeAsset) { _, newValue in
            if let a = newValue, !a.isEmpty { asset = a; appState.pendingAddTradeAsset = nil }
        }
        .sheet(item: $tradeToEdit) { t in
            EditTradeSheet(trade: t, onDismiss: { tradeToEdit = nil }, onSave: { updated in
                appState.updateTrade(updated)
                tradeToEdit = nil
            })
        }
    }

    private var sortedTrades: [Trade] {
        let list = appState.filteredTrades()
        let order: (Trade, Trade) -> Bool
        switch sortKey {
        case "Asset": order = { $0.asset < $1.asset }
        case "Type": order = { $0.type < $1.type }
        case "Total": order = { $0.total_value < $1.total_value }
        default: order = { $0.date < $1.date }
        }
        return list.sorted { sortAscending ? order($0, $1) : order($1, $0) }
    }

    private func setSort(_ key: String) {
        if sortKey == key { sortAscending.toggle() } else { sortKey = key; sortAscending = false }
    }

    /// Buttons 25/50/75/100% for quick-fill (e.g. price = % of market, quantity = % of holding).
    private func quickAddPercentRow(label: String, fill: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            Text("\(label):").font(.caption2).foregroundColor(.secondary)
            ForEach([25, 50, 75, 100], id: \.self) { pct in
                Button("\(pct)%") { fill(pct) }.buttonStyle(.borderless).font(.caption2)
            }
        }
    }

    /// Format double for price/quantity fields (avoid scientific notation).
    private func formatDecimal(_ value: Double) -> String {
        if value == 0 { return "0" }
        if abs(value) >= 0.01 && abs(value) < 1_000_000 { return String(format: "%.8g", value) }
        return String(format: "%.4f", value)
    }

    private var transactionTableHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Date").frame(width: 120, alignment: .leading).font(.caption).foregroundColor(.secondary)
            Text("Asset").frame(width: 44, alignment: .leading).font(.caption).foregroundColor(.secondary)
            Text("Type").frame(width: 52, alignment: .leading).font(.caption).foregroundColor(.secondary)
            Text("Price").frame(width: 64, alignment: .trailing).font(.caption).foregroundColor(.secondary)
            Text("Qty").frame(width: 64, alignment: .trailing).font(.caption).foregroundColor(.secondary)
            Text("Δ Asset").frame(width: 56, alignment: .trailing).font(.caption).foregroundColor(.secondary)
            Text("Δ USD").frame(width: 64, alignment: .trailing).font(.caption).foregroundColor(.secondary)
            Text("Exchange").frame(width: 64, alignment: .leading).font(.caption).foregroundColor(.secondary)
            Text("Order").frame(width: 72, alignment: .leading).font(.caption).foregroundColor(.secondary)
            Text("Account").frame(width: 60, alignment: .leading).font(.caption).foregroundColor(.secondary)
            Text("Fee").frame(width: 48, alignment: .trailing).font(.caption).foregroundColor(.secondary)
            Text("Total").frame(width: 68, alignment: .trailing).font(.caption).foregroundColor(.secondary)
            Text("Profit").frame(width: 72, alignment: .trailing).font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func transactionRow(_ trade: Trade) -> some View {
        let pnlUsd = appState.displayProfitForTrade(trade)
        let (deltaAsset, deltaUsd) = accumulationDeltas(trade)
        return HStack(alignment: .center, spacing: 8) {
            Text(trade.date).frame(width: 120, alignment: .leading).font(.caption)
            Text(trade.asset).frame(width: 44, alignment: .leading).font(.caption)
            Text(trade.type).frame(width: 52, alignment: .leading).font(.caption)
            AnimatedNumberText(value: trade.price, format: .plain(4), font: .caption).frame(width: 64, alignment: .trailing)
            AnimatedNumberText(value: trade.quantity, format: .plain(4), font: .caption).frame(width: 64, alignment: .trailing)
            Text(deltaAsset).frame(width: 56, alignment: .trailing).font(.caption)
            Text(deltaUsd).frame(width: 64, alignment: .trailing).font(.caption)
            Text(trade.exchange).frame(width: 64, alignment: .leading).font(.caption)
            Text(trade.order_type.isEmpty ? "—" : trade.order_type).frame(width: 72, alignment: .leading).font(.caption)
            Text(appState.accountName(for: trade.account_id)).frame(width: 60, alignment: .leading).font(.caption)
            AnimatedNumberText(value: trade.fee, format: .currency, font: .caption).frame(width: 48, alignment: .trailing)
            AnimatedNumberText(value: trade.total_value, format: .currency, font: .caption).frame(width: 68, alignment: .trailing)
            Group {
                if let pnl = pnlUsd {
                    if appState.profitDisplayCurrency == "BTC", let btc = appState.btcPrice(), btc > 0 {
                        AnimatedNumberText(value: pnl / btc, format: .currencyBtc, color: pnl >= 0 ? .green : .red, font: .caption)
                    } else {
                        AnimatedNumberText(value: pnl, format: .currency, color: pnl >= 0 ? .green : .red, font: .caption)
                    }
                } else {
                    Text("—").font(.caption).foregroundColor(.secondary)
                }
            }.frame(width: 72, alignment: .trailing)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    /// Signed delta for this trade: Δ Asset (quantity), Δ USD (total value). BUY: +qty, -total_value; SELL: -qty, +total_value; etc.
    private func accumulationDeltas(_ trade: Trade) -> (String, String) {
        let qty: Double
        let usd: Double
        switch trade.type {
        case "BUY", "Transfer", "Deposit": qty = trade.quantity; usd = -(trade.total_value + trade.fee)
        case "SELL", "Withdrawal": qty = -trade.quantity; usd = trade.total_value - trade.fee
        default: qty = 0; usd = 0
        }
        let assetStr = qty == 0 ? "—" : (qty > 0 ? "+" : "") + String(format: "%.4f", qty)
        let usdStr = usd == 0 ? "—" : (usd > 0 ? "+" : "") + String(format: "$%.2f", usd)
        return (assetStr, usdStr)
    }

    private func addTrade() {
        guard let q = Double(quantity), let p = Double(price), q > 0, p >= 0 else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let totalValue = q * p
        var orderTypeStr = orderType
        if orderType == "Limit" {
            if orderPostOnly { orderTypeStr += ",Post-only" }
            if orderGTC { orderTypeStr += ",GTC" }
            if orderGTD { orderTypeStr += ",GTD" }
        }
        let feeComputed = appState.computedFee(totalValue: totalValue, exchange: exchange, orderType: orderTypeStr)
        let accountId = selectedAccountId.isEmpty ? appState.data.accounts.first?.id : selectedAccountId
        let trade = Trade(
            id: UUID().uuidString,
            date: formatter.string(from: Date()),
            asset: asset,
            type: type,
            price: p,
            quantity: q,
            exchange: exchange,
            order_type: orderTypeStr,
            fee: feeComputed,
            total_value: totalValue,
            account_id: accountId,
            is_client_trade: isSidecarTrade ? true : nil,
            client_name: isSidecarTrade && !sidecarClientName.isEmpty ? sidecarClientName : nil,
            client_percentage: nil
        )
        appState.addTrade(trade)
        quantity = ""
        price = ""
        if isSidecarTrade { sidecarClientName = "" }
    }
}

// MARK: - Edit Trade sheet

struct EditTradeSheet: View {
    @EnvironmentObject var appState: AppState
    let trade: Trade
    let onDismiss: () -> Void
    let onSave: (Trade) -> Void
    @State private var asset: String = ""
    @State private var type: String = "BUY"
    @State private var quantity: String = ""
    @State private var price: String = ""
    @State private var exchange: String = "Bitstamp"
    @State private var orderType: String = "Market"
    @State private var orderPostOnly = false
    @State private var orderGTC = false
    @State private var orderGTD = false
    @State private var selectedAccountId: String = ""
    @State private var isSidecarTrade = false
    @State private var sidecarClientName: String = ""
    @State private var tradeDate = Date()

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Trade").font(.headline)
            Form {
                HStack {
                    Picker("Asset", selection: $asset) {
                        ForEach(["BTC", "ETH", "BNB", "DENT", "USDC", "USDT", "USD"], id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Type", selection: $type) {
                        ForEach(["BUY", "SELL", "Transfer", "Deposit", "Withdrawal"], id: \.self) { Text($0).tag($0) }
                    }
                }
                HStack {
                    TextField("Quantity", text: $quantity)
                    TextField("Price", text: $price)
                }
                Picker("Exchange", selection: $exchange) {
                    ForEach(Array(appState.data.settings.fee_structure.keys.sorted()), id: \.self) { Text($0).tag($0) }
                }
                Picker("Order type", selection: $orderType) {
                    Text("Market").tag("Market")
                    Text("Limit").tag("Limit")
                }
                HStack(spacing: 16) {
                    Toggle("Post-only", isOn: $orderPostOnly).toggleStyle(.checkbox)
                    Toggle("GTC", isOn: $orderGTC).toggleStyle(.checkbox)
                    Toggle("GTD", isOn: $orderGTD).toggleStyle(.checkbox)
                }
                .disabled(orderType != "Limit")
                Picker("Account", selection: $selectedAccountId) {
                    Text("(No account)").tag("")
                    ForEach(appState.data.accounts, id: \.id) { Text($0.name).tag($0.id) }
                }
                Toggle("Sidecar Trade", isOn: $isSidecarTrade)
                if isSidecarTrade {
                    Picker("Sidecar client", selection: $sidecarClientName) {
                        Text("(None)").tag("")
                        ForEach(appState.users.filter { $0 != appState.currentUser }, id: \.self) { Text($0).tag($0) }
                    }
                }
                DatePicker("Date", selection: $tradeDate, displayedComponents: [.date, .hourAndMinute])
            }
            HStack {
                Button("Cancel") { onDismiss() }
                Button("Save") { save() }.buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400)
        .onAppear {
            asset = trade.asset
            type = trade.type
            quantity = String(trade.quantity)
            price = String(trade.price)
            exchange = trade.exchange
            let parts = trade.order_type.split(separator: ",").map(String.init)
            orderType = parts.first.flatMap { $0 == "Limit" || $0 == "Market" ? $0 : "Market" } ?? "Market"
            orderPostOnly = parts.contains("Post-only")
            orderGTC = parts.contains("GTC")
            orderGTD = parts.contains("GTD")
            selectedAccountId = trade.account_id ?? ""
            isSidecarTrade = trade.is_client_trade ?? false
            sidecarClientName = trade.client_name ?? ""
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            f.locale = Locale(identifier: "en_US_POSIX")
            tradeDate = f.date(from: trade.date) ?? Date()
        }
    }

    private func save() {
        guard let q = Double(quantity), let p = Double(price), q > 0, p >= 0 else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let totalValue = q * p
        var orderTypeStr = orderType
        if orderType == "Limit" {
            if orderPostOnly { orderTypeStr += ",Post-only" }
            if orderGTC { orderTypeStr += ",GTC" }
            if orderGTD { orderTypeStr += ",GTD" }
        }
        let feeComputed = appState.computedFee(totalValue: totalValue, exchange: exchange, orderType: orderTypeStr)
        let accountId = selectedAccountId.isEmpty ? nil : selectedAccountId
        var updated = trade
        updated.date = formatter.string(from: tradeDate)
        updated.asset = asset
        updated.type = type
        updated.price = p
        updated.quantity = q
        updated.exchange = exchange
        updated.order_type = orderTypeStr
        updated.fee = feeComputed
        updated.total_value = totalValue
        updated.account_id = accountId
        updated.is_client_trade = isSidecarTrade ? true : nil
        updated.client_name = isSidecarTrade && !sidecarClientName.isEmpty ? sidecarClientName : nil
        updated.client_percentage = nil
        onSave(updated)
    }
}

// MARK: - Triggered alerts section (standalone to avoid EnvironmentObject wrapper issues)

struct TriggeredAlertsSectionView: View {
    let alerts: [(id: String, message: String)]
    let onDismiss: () -> Void

    var body: some View {
        Group {
            if !alerts.isEmpty {
                Divider()
                Text("Alerts").font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(alerts.enumerated()), id: \.offset) { _, a in
                        Text(a.message).font(.caption).foregroundColor(.orange)
                    }
                    Button("Dismiss alerts", action: onDismiss).buttonStyle(.borderless).font(.caption)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Assistant tab (query/command-style questions)

struct AssistantTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var queryText = ""
    @State private var responseText = "Ask: portfolio, positions, positions BTC, pnl, refresh."
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask about your portfolio in plain language (no LLM; uses built-in query).")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                TextField("e.g. portfolio, positions, pnl, refresh", text: $queryText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitQuery() }
                    .focused($queryFocused)
                Button("Ask") { submitQuery() }
                    .buttonStyle(.borderedProminent)
            }
            ScrollView {
                Text(responseText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)
            }
            .frame(minHeight: 120)
        }
        .padding(16)
    }

    private func submitQuery() {
        queryFocused = false
        responseText = appState.answerAssistantQuery(queryText)
    }
}

// MARK: - Polymarket tab (crypto markets, arbitrage, scalping, strategy breakdown)

struct PolymarketTabView: View {
    @State private var events: [PolymarketEvent] = []
    @State private var loading = false
    @State private var loadError: String?
    @AppStorage("FuckYouMoney.polymarketGammaBaseURL") private var polymarketGammaBaseURL = ""
    @AppStorage("FuckYouMoney.polymarketClobBaseURL") private var polymarketClobBaseURL = ""
    private var polymarketService: PolymarketService {
        PolymarketService(
            gammaBaseURL: polymarketGammaBaseURL.isEmpty ? nil : polymarketGammaBaseURL,
            clobBaseURL: polymarketClobBaseURL.isEmpty ? nil : polymarketClobBaseURL
        )
    }

    /// Markets with positive arb gap (YES + NO < 1) from loaded events.
    private var arbOpportunities: [(event: PolymarketEvent, market: PolymarketMarket)] {
        var out: [(PolymarketEvent, PolymarketMarket)] = []
        for event in events {
            for market in event.markets where (market.arbGap ?? 0) > 0 {
                out.append((event, market))
            }
        }
        return out.sorted { ($0.market.arbGap ?? 0) > ($1.market.arbGap ?? 0) }
    }

    /// Markets with end date soon (within 14 days) and an outcome priced ≥ 0.95 (endgame arb).
    private var endgameArbCandidates: [(event: PolymarketEvent, market: PolymarketMarket, outcomeIndex: Int, price: Double)] {
        let calendar = Calendar.current
        let now = Date()
        let isoFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            return f
        }()
        let fallbackFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            return f
        }()
        var out: [(PolymarketEvent, PolymarketMarket, Int, Double)] = []
        for event in events {
            for market in event.markets {
                guard let endStr = market.endDate else { continue }
                let endDate: Date? = isoFormatter.date(from: endStr)
                    ?? fallbackFormatter.date(from: String(endStr.prefix(10)))
                guard let end = endDate else { continue }
                let days = calendar.dateComponents([.day], from: now, to: end).day ?? 999
                guard days >= 0, days <= 14 else { continue }
                for (i, p) in market.outcomePrices.enumerated() where p >= 0.95 {
                    out.append((event, market, i, p))
                    break
                }
            }
        }
        return out.sorted { $0.3 > $1.3 }
    }

    /// Markets with high YES price (candidate for systematic NO). YES price ≥ 0.65, has end date.
    private var systematicNoCandidates: [(event: PolymarketEvent, market: PolymarketMarket)] {
        var out: [(PolymarketEvent, PolymarketMarket)] = []
        for event in events {
            for market in event.markets {
                guard let yesIdx = market.outcomes.firstIndex(of: "Yes"),
                      yesIdx < market.outcomePrices.count,
                      market.outcomePrices[yesIdx] >= 0.65,
                      market.endDate != nil else { continue }
                out.append((event, market))
            }
        }
        return out.sorted { item1, item2 in
            let y1 = item1.market.outcomes.firstIndex(of: "Yes").flatMap { i in i < item1.market.outcomePrices.count ? item1.market.outcomePrices[i] : nil } ?? 0
            let y2 = item2.market.outcomes.firstIndex(of: "Yes").flatMap { i in i < item2.market.outcomePrices.count ? item2.market.outcomePrices[i] : nil } ?? 0
            return y1 > y2
        }
    }

    /// Markets with 3+ outcomes where sum of outcome prices < $1 (combinatorial arb: buy all outcomes for locked profit).
    private var combinatorialArbCandidates: [(event: PolymarketEvent, market: PolymarketMarket)] {
        var out: [(PolymarketEvent, PolymarketMarket)] = []
        for event in events {
            for market in event.markets where market.outcomes.count >= 3 && market.outcomePrices.count >= 3 {
                let sum = market.outcomePrices.prefix(market.outcomes.count).reduce(0, +)
                guard sum > 0, sum < 1 else { continue }
                out.append((event, market))
            }
        }
        return out.sorted { m1, m2 in
            let s1 = m1.market.outcomePrices.prefix(m1.market.outcomes.count).reduce(0, +)
            let s2 = m2.market.outcomePrices.prefix(m2.market.outcomes.count).reduce(0, +)
            return (1 - s1) > (1 - s2)
        }
    }

    @State private var spreadMarketSelection: (event: PolymarketEvent, market: PolymarketMarket)?
    @State private var orderBook: OrderBookSnapshot?
    @State private var orderBookLoading = false
    @AppStorage("FuckYouMoney.polymarketScalpAlertEnabled") private var scalpAlertEnabled = false
    @AppStorage("FuckYouMoney.polymarketScalpAlertThresholdPct") private var scalpAlertThresholdPct = "5"
    @State private var lastScalpNotifiedTokenId: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Crypto markets
                Section {
                    if loading {
                        HStack { ProgressView(); Text("Loading crypto markets…").foregroundColor(.secondary) }
                            .padding()
                    } else if let err = loadError {
                        Text(err).foregroundColor(.red).font(.caption).padding()
                    } else if events.isEmpty {
                        Text("No crypto-related markets found. Pull to refresh.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(events, id: \.id) { event in
                                polymarketEventRow(event)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                } header: {
                    Text("Crypto markets")
                        .font(.headline)
                } footer: {
                    Text("Data from Polymarket Gamma API. Prices are probabilities (Yes + No ≈ $1).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Arbitrage opportunities (from loaded events)
                Section {
                    if arbOpportunities.isEmpty && !events.isEmpty {
                        Text("No intra-market arb (YES + NO < $1) in current list. Open on Polymarket for full book.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else if !arbOpportunities.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(arbOpportunities.prefix(20).enumerated()), id: \.offset) { _, item in
                                arbRow(event: item.event, market: item.market)
                            }
                        }
                    } else {
                        Text("Load crypto markets above to see arb opportunities.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Arbitrage opportunities")
                        .font(.headline)
                } footer: {
                    Text("Intra-market: buy both YES and NO when sum < $1 for locked profit. Combinatorial and endgame arb below.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Combinatorial arbitrage (multi-outcome sum < $1)
                Section {
                    if combinatorialArbCandidates.isEmpty && !events.isEmpty {
                        Text("No combinatorial arb in current list (multi-outcome markets where sum of prices < $1).")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else if !combinatorialArbCandidates.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(combinatorialArbCandidates.prefix(15).enumerated()), id: \.offset) { _, item in
                                combinatorialArbRow(event: item.event, market: item.market)
                            }
                        }
                    } else {
                        Text("Load crypto markets above to see combinatorial opportunities.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Combinatorial arbitrage")
                        .font(.headline)
                } footer: {
                    Text("Multi-outcome markets: buy one share of each outcome when sum < $1 for locked profit.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Endgame arbitrage (resolves soon, high probability)
                Section {
                    if endgameArbCandidates.isEmpty && !events.isEmpty {
                        Text("No endgame arb in current list (outcome ≥95% and resolves within 14 days).")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else if !endgameArbCandidates.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(endgameArbCandidates.prefix(15).enumerated()), id: \.offset) { _, item in
                                endgameArbRow(event: item.event, market: item.market, outcomeIndex: item.outcomeIndex, price: item.price)
                            }
                        }
                    } else {
                        Text("Load crypto markets above to see endgame opportunities.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Endgame arbitrage")
                        .font(.headline)
                } footer: {
                    Text("Buy near-certain outcomes (95%+) close to resolution for implied yield.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Scalping / spread – CLOB order book
                Section {
                    if !events.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Select a market to view live order book (CLOB):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(Array(events.prefix(8).enumerated()), id: \.element.id) { _, event in
                                if let m = event.markets.first, !m.clobTokenIds.isEmpty {
                                    Button {
                                        spreadMarketSelection = (event, m)
                                        Task { await loadOrderBook(for: m) }
                                    } label: {
                                        HStack {
                                            Text(event.title).lineLimit(1).font(.caption)
                                            Spacer()
                                            Image(systemName: "book.closed")
                                        }
                                        .padding(6)
                                        .background(spreadMarketSelection?.event.id == event.id ? Color.accentColor.opacity(0.15) : Color.clear)
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            if orderBookLoading {
                                HStack { ProgressView(); Text("Loading order book…").font(.caption).foregroundColor(.secondary) }
                            }
                            if let book = orderBook {
                                spreadView(book)
                                HStack {
                                    Button("Refresh book") { Task { if let m = spreadMarketSelection?.market { await loadOrderBook(for: m) } } }
                                        .buttonStyle(.bordered)
                                    Text("Notify when spread >")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("5", text: $scalpAlertThresholdPct)
                                        .frame(width: 36)
                                        .textFieldStyle(.roundedBorder)
                                    Text("%").font(.caption)
                                    Toggle("Alert", isOn: $scalpAlertEnabled)
                                        .labelsHidden()
                                        .onChange(of: scalpAlertEnabled) { if scalpAlertEnabled { requestScalpNotificationPermission() } }
                                }
                                .padding(.top, 4)
                            }
                        }
                    } else {
                        Text("Load crypto markets above, then pick a market to view spread.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Scalping / spread view")
                        .font(.headline)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fee note: Polymarket typically charges a percentage on winnings (e.g. 2%).")
                        Text("Allow notifications (when turning on Alert) to receive spread alerts.")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }

                // Systematic NO farming
                Section {
                    if systematicNoCandidates.isEmpty && !events.isEmpty {
                        Text("No high-YES markets in current list. Many prediction markets resolve NO; betting NO on overpriced YES can have edge.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else if !systematicNoCandidates.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(systematicNoCandidates.prefix(15).enumerated()), id: \.offset) { _, item in
                                systematicNoRow(event: item.event, market: item.market)
                            }
                        }
                    } else {
                        Text("Load crypto markets above to see NO value candidates.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Systematic NO (high YES price)")
                        .font(.headline)
                } footer: {
                    Text("Markets where YES is priced high; NO may offer value. Many markets resolve NO. Not financial advice.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Strategy breakdown (education)
                Section {
                    DisclosureGroup("Ways to make money on Polymarket") {
                        VStack(alignment: .leading, spacing: 8) {
                            strategyRow("Intra-market arbitrage", "YES + NO < $1 → buy both for locked profit.")
                            strategyRow("Combinatorial arbitrage", "Multi-outcome markets where sum of prices < $1.")
                            strategyRow("Endgame arbitrage", "Buy near-certain outcomes (95–99%) close to resolution.")
                            strategyRow("Spread farming / scalping", "Capture bid–ask repeatedly; structural spread lock.")
                            strategyRow("Systematic NO farming", "Bet NO on overpriced YES; many markets resolve NO.")
                            strategyRow("Cross-platform arbitrage", "Same outcome at different price on Polymarket vs Kalshi etc. Compare across platforms.")
                            HStack(spacing: 12) {
                                Link("Polymarket docs", destination: URL(string: "https://docs.polymarket.com")!)
                                Link("Kalshi (compare)", destination: URL(string: "https://kalshi.com/markets")!)
                            }
                            .font(.caption)
                        }
                        .padding(.top, 6)
                    }
                } header: {
                    Text("Strategy breakdown")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .refreshable { await loadCryptoEvents() }
        .task { await loadCryptoEvents() }
    }

    private func polymarketEventRow(_ event: PolymarketEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
            if let m = event.markets.first {
                HStack(spacing: 12) {
                    ForEach(Array(m.outcomes.enumerated()), id: \.offset) { i, outcome in
                        let price = i < m.outcomePrices.count ? m.outcomePrices[i] : 0
                        Text("\(outcome): \(formatPct(price))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            if let url = event.eventURL {
                Link("View on Polymarket", destination: url)
                    .font(.caption)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private func arbRow(event: PolymarketEvent, market: PolymarketMarket) -> some View {
        let gap = market.arbGap ?? 0
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(market.question)
                    .font(.caption)
                    .lineLimit(1)
                Text("Arb gap: \(formatPct(gap))")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
            Spacer()
            if let url = event.eventURL {
                Link("Open", destination: url).font(.caption)
            }
        }
        .padding(8)
        .background(Color.green.opacity(0.08))
        .cornerRadius(6)
    }

    private func strategyRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).fontWeight(.medium)
            Text(detail).font(.caption).foregroundColor(.secondary)
        }
    }

    private func formatPct(_ value: Double) -> String {
        let pct = value * 100
        return String(format: "%.1f%%", pct)
    }

    private func spreadView(_ book: OrderBookSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                if let s = book.spread { Text("Spread: \(formatPct(s))").font(.caption).fontWeight(.medium) }
                if let m = book.midpoint { Text("Mid: \(formatPct(m))").font(.caption).foregroundColor(.secondary) }
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bids").font(.caption2).foregroundColor(.secondary)
                    ForEach(Array(book.bids.prefix(5).enumerated()), id: \.offset) { _, b in
                        Text("\(formatPct(b.price)) × \(String(format: "%.0f", b.size))").font(.caption2)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Asks").font(.caption2).foregroundColor(.secondary)
                    ForEach(Array(book.asks.prefix(5).enumerated()), id: \.offset) { _, a in
                        Text("\(formatPct(a.price)) × \(String(format: "%.0f", a.size))").font(.caption2)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private func endgameArbRow(event: PolymarketEvent, market: PolymarketMarket, outcomeIndex: Int, price: Double) -> some View {
        let outcomeName = outcomeIndex < market.outcomes.count ? market.outcomes[outcomeIndex] : "Outcome"
        let daysStr = market.endDate.flatMap { end in
            let iso = String(end.prefix(10))
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            guard let d = f.date(from: iso) else { return nil }
            let days = Calendar.current.dateComponents([.day], from: Date(), to: d).day ?? 0
            return "\(days) days"
        } ?? "—"
        let impliedYield = daysStr != "—" ? String(format: "%.0f%%", (1 - price) / price * 100) : "—"
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(market.question).font(.caption).lineLimit(2)
                Text("\(outcomeName) \(formatPct(price)) · Resolves in \(daysStr) · Implied yield \(impliedYield)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let url = event.eventURL {
                Link("Open", destination: url).font(.caption)
            }
        }
        .padding(8)
        .background(Color.purple.opacity(0.08))
        .cornerRadius(6)
    }

    /// Row for combinatorial arb: multi-outcome market with sum of prices < $1.
    private func combinatorialArbRow(event: PolymarketEvent, market: PolymarketMarket) -> some View {
        let n = min(market.outcomes.count, market.outcomePrices.count)
        let sum = market.outcomePrices.prefix(n).reduce(0, +)
        let gap = 1 - sum
        let outcomeSummary = (0..<n).map { i in
            "\(market.outcomes[i]) \(formatPct(market.outcomePrices[i]))"
        }.joined(separator: " · ")
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(market.question).font(.caption).lineLimit(2)
                Text("\(outcomeSummary)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Sum \(formatPct(sum)) → gap \(String(format: "%.1f", gap * 100))%")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
            Spacer()
            if let url = event.eventURL {
                Link("Open", destination: url).font(.caption)
            }
        }
        .padding(8)
        .background(Color.teal.opacity(0.08))
        .cornerRadius(6)
    }

    private func systematicNoRow(event: PolymarketEvent, market: PolymarketMarket) -> some View {
        let yesPct = market.outcomes.firstIndex(of: "Yes").flatMap { i in i < market.outcomePrices.count ? market.outcomePrices[i] : nil } ?? 0
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(market.question).font(.caption).lineLimit(2)
                Text("YES \(formatPct(yesPct)) · End: \(market.endDate?.prefix(10) ?? "—")").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if let url = event.eventURL {
                Link("Open", destination: url).font(.caption)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
    }

    /// Requests notification permission when user enables the scalp Alert toggle.
    private func requestScalpNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func loadOrderBook(for market: PolymarketMarket) async {
        guard let tokenId = market.clobTokenIds.first else { return }
        orderBookLoading = true
        orderBook = nil
        defer { orderBookLoading = false }
        let book = await polymarketService.fetchOrderBook(tokenId: tokenId)
        orderBook = book
        if let book = book, scalpAlertEnabled {
            let threshold = (Double(scalpAlertThresholdPct) ?? 5) / 100
            if (book.spread ?? 0) >= threshold, lastScalpNotifiedTokenId != tokenId {
                lastScalpNotifiedTokenId = tokenId
                let content = UNMutableNotificationContent()
                content.title = "Polymarket spread alert"
                content.body = "Spread \(String(format: "%.1f", (book.spread ?? 0) * 100))% ≥ \(scalpAlertThresholdPct)% — \(market.question)"
                content.sound = .default
                let request = UNNotificationRequest(identifier: "polymarket-scalp-\(tokenId)-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
            }
        }
    }

    private func loadCryptoEvents() async {
        loading = true
        loadError = nil
        defer { loading = false }
        let fetched = await polymarketService.fetchCryptoEvents(limitPerQuery: 50)
        if fetched.isEmpty {
            // Fallback: fetch active events by volume and filter by keyword
            let all = await polymarketService.fetchEvents(active: true, closed: false, limit: 80, slugContains: nil, order: "volume_24hr", ascending: false)
            let keywords = ["bitcoin", "crypto", "ethereum", "btc", "eth", "solana", "polygon", "matic", "token", "price"]
            events = all.filter { e in
                let lower = (e.title + " " + e.slug).lowercased()
                return keywords.contains { lower.contains($0) }
            }
            if events.isEmpty {
                loadError = "Could not load markets. Check network."
            }
        } else {
            events = fetched
        }
    }
}

// MARK: - Assets tab (per-asset info: price since open, metrics, performance, technicals)

struct AssetsTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedAsset: String = ""
    @State private var assetMarketData: AssetMarketData?
    @State private var assetMarketDataLoading = false
    /// YTD % (Jan 1 → now) from historical price fetch; nil for stablecoins or when unavailable.
    @State private var ytdPct: Double? = nil
    @AppStorage("FuckYouMoney.watchlistAssets") private var watchlistRaw = ""
    @State private var watchlistAddSymbol: String = ""

    /// Held assets from current portfolio metrics (sorted).
    private var heldAssets: [String] {
        guard let pm = appState.portfolioMetrics else { return [] }
        return pm.per_asset.keys.filter { asset in
            let pa = pm.per_asset[asset]!
            return (pa.units_held + pa.holding_qty) > 0
        }.sorted()
    }

    /// Watchlist symbols (persisted); uppercase, no empty.
    private var watchlistAssets: [String] {
        watchlistRaw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
    }

    /// Held first, then watchlist-only (no duplicate), so user can pick any.
    private var allSelectableAssets: [String] {
        let heldSet = Set(heldAssets)
        let watchOnly = watchlistAssets.filter { !heldSet.contains($0) }
        return (heldAssets + watchOnly).filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                watchlistSection
                if allSelectableAssets.isEmpty {
                    Text("No held or watched assets. Add trades (Transactions) or add symbols to the watchlist above.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    assetPickerSection
                    if !selectedAsset.isEmpty {
                        if assetMarketDataLoading {
                            HStack {
                                ProgressView().scaleEffect(0.8)
                                Text("Loading market data…").font(.caption).foregroundColor(.secondary)
                            }
                            .padding(8)
                        }
                        priceAnd24hSection
                        marketMetricsSection
                        performanceSection
                        technicalsSection
                        assetInfoSection
                    }
                }
            }
            .padding()
        }
        .onAppear {
            if selectedAsset.isEmpty, let first = allSelectableAssets.first {
                selectedAsset = first
            }
        }
        .onChange(of: heldAssets.count) { _ in
            if selectedAsset.isEmpty, let first = allSelectableAssets.first {
                selectedAsset = first
            }
            if !allSelectableAssets.contains(selectedAsset), let first = allSelectableAssets.first {
                selectedAsset = first
            }
        }
        .onChange(of: watchlistRaw) { _ in
            if !allSelectableAssets.contains(selectedAsset), let first = allSelectableAssets.first {
                selectedAsset = first
            }
        }
        .task(id: selectedAsset) {
            guard !selectedAsset.isEmpty else { return }
            assetMarketDataLoading = true
            assetMarketData = nil
            ytdPct = nil
            let pricing = PricingService()
            let data = await pricing.fetchAssetMarketData(asset: selectedAsset)
            await MainActor.run {
                assetMarketData = data
                assetMarketDataLoading = false
            }
            // YTD: Jan 1 of current year → current price (skip stablecoins).
            let assetForYtd = selectedAsset
            let upper = assetForYtd.uppercased()
            if upper != "USD" && upper != "USDC" && upper != "USDT", let data = await MainActor.run(body: { assetMarketData }), data.price > 0 {
                let cal = Calendar.current
                let year = cal.component(.year, from: Date())
                guard let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1)) else { return }
                if let jan1Price = await pricing.fetchHistoricalPrice(asset: assetForYtd, date: jan1), jan1Price > 0 {
                    let pct = (data.price - jan1Price) / jan1Price * 100
                    await MainActor.run {
                        if selectedAsset == assetForYtd { ytdPct = pct }
                    }
                }
            }
        }
    }

    private var watchlistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Watchlist").font(.headline)
            HStack(spacing: 8) {
                TextField("Symbol (e.g. SOL)", text: $watchlistAddSymbol)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Button("Add") {
                    let sym = watchlistAddSymbol.trimmingCharacters(in: .whitespaces).uppercased()
                    guard !sym.isEmpty else { return }
                    var list = watchlistAssets
                    if !list.contains(sym) {
                        list.append(sym)
                        watchlistRaw = list.joined(separator: ",")
                    }
                    watchlistAddSymbol = ""
                }
                .buttonStyle(.bordered)
            }
            if !watchlistAssets.isEmpty {
                ForEach(watchlistAssets, id: \.self) { sym in
                    HStack(spacing: 6) {
                        Text(sym).font(.caption)
                        Spacer()
                        Button("Remove") { removeFromWatchlist(sym) }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private func removeFromWatchlist(_ symbol: String) {
        let list = watchlistAssets.filter { $0 != symbol }
        watchlistRaw = list.joined(separator: ",")
    }

    private var assetPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Asset").font(.headline)
            HStack(spacing: 12) {
                Picker("", selection: $selectedAsset) {
                    ForEach(allSelectableAssets, id: \.self) { asset in
                        Text(asset).tag(asset)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
                if !selectedAsset.isEmpty {
                    Button("Add trade…") {
                        appState.pendingAddTradeAsset = selectedAsset
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    /// Current price and 24h change (proxy for "since market open" via 24h %).
    private var priceAnd24hSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Price & 24h change").font(.headline)
            if let d = assetMarketData {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(assetsFormatCurrency(d.price)).font(.title2).fontWeight(.semibold)
                    if let pct = d.priceChangePct24h {
                        Text(String(format: "%+.2f%%", pct))
                            .font(.subheadline)
                            .foregroundColor(pct >= 0 ? .green : .red)
                    }
                }
                if let delta = d.priceChange24h {
                    Text("24h change: \(assetsFormatCurrency(delta))").font(.caption).foregroundColor(.secondary)
                }
            } else {
                Text("Load market data for price and 24h % (proxy for change since session).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    /// Trading volume 24h, market cap, FDV, volume/mcap, circulating supply (from CoinGecko when loaded).
    private var marketMetricsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Market metrics").font(.headline)
            if let d = assetMarketData {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 8) {
                    if let v = d.volume24h {
                        assetsMetricRow("24h volume", value: assetsFormatCurrency(v))
                    }
                    if let m = d.marketCap {
                        assetsMetricRow("Market cap", value: assetsFormatCurrency(m))
                    }
                    if let fdv = d.fullyDilutedValuation {
                        assetsMetricRow("Fully diluted val.", value: assetsFormatCurrency(fdv))
                    }
                    if let ratio = d.volumeToMarketCap {
                        assetsMetricRow("Vol / market cap", value: String(format: "%.4f", ratio))
                    }
                    if let supply = d.circulatingSupply {
                        assetsMetricRow("Circulating supply", value: String(format: "%.2f", supply))
                    }
                }
            } else {
                Text("24h volume, market cap, FDV, volume/mcap, circulating supply. Load market data (CoinGecko).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private func assetsMetricRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption).fontWeight(.medium)
        }
    }

    private func assetsFormatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        if value >= 1_000_000_000 {
            return (formatter.string(from: NSNumber(value: value / 1_000_000_000)) ?? "—") + "B"
        }
        if value >= 1_000_000 {
            return (formatter.string(from: NSNumber(value: value / 1_000_000)) ?? "—") + "M"
        }
        if value >= 1_000 {
            return (formatter.string(from: NSNumber(value: value / 1_000)) ?? "—") + "K"
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    /// Performance 1W, 1M, 3M, 6M, 1Y from CoinGecko (7d, 30d, 60d, 200d, 1y).
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance").font(.headline)
            if let d = assetMarketData {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                    if let p = d.pct7d { assetsPerfChip("1W", pct: p) }
                    if let p = d.pct14d { assetsPerfChip("14d", pct: p) }
                    if let p = d.pct30d { assetsPerfChip("1M", pct: p) }
                    if let p = d.pct60d { assetsPerfChip("2M", pct: p) }
                    if let p = d.pct200d { assetsPerfChip("~6M", pct: p) }
                    if let p = d.pct1y { assetsPerfChip("1Y", pct: p) }
                    if let p = ytdPct { assetsPerfChip("YTD", pct: p) }
                }
            } else {
                Text("1W, 1M, 2M, ~6M, 1Y, YTD (from Jan 1). Load market data.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private func assetsPerfChip(_ label: String, pct: Double) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(String(format: "%+.1f%%", pct))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(pct >= 0 ? .green : .red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }

    /// Technicals: community sentiment from CoinGecko (votes up % → Strong Sell … Strong Buy).
    private var technicalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Technicals").font(.headline)
            if let d = assetMarketData, let up = d.sentimentVotesUpPct {
                let label = assetsSentimentLabel(upPct: up)
                HStack(spacing: 8) {
                    Text("Community sentiment:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(assetsSentimentColor(upPct: up))
                }
                if let down = d.sentimentVotesDownPct {
                    Text("Votes: \(String(format: "%.0f", up))% up, \(String(format: "%.0f", down))% down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Community sentiment (CoinGecko) when market data is loaded. Full TA (Strong Sell … Strong Buy) may use a dedicated API later.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private func assetsSentimentLabel(upPct: Double) -> String {
        switch upPct {
        case 70...: return "Strong Buy"
        case 55..<70: return "Buy"
        case 45..<55: return "Neutral"
        case 30..<45: return "Sell"
        default: return "Strong Sell"
        }
    }

    private func assetsSentimentColor(upPct: Double) -> Color {
        switch upPct {
        case 55...: return .green
        case 45..<55: return .secondary
        default: return .red
        }
    }

    /// Asset name, description (truncated), and homepage from CoinGecko when loaded.
    private var assetInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Asset info").font(.headline)
            if let d = assetMarketData {
                if let name = d.name, !name.isEmpty {
                    Text(name).font(.subheadline).fontWeight(.semibold)
                }
                if let desc = d.assetDescription, !desc.isEmpty {
                    let truncated = desc.count > 320 ? String(desc.prefix(320)) + "…" : desc
                    Text(truncated)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let urlStr = d.homepage, !urlStr.isEmpty, let url = URL(string: urlStr) {
                    Link("Homepage", destination: url)
                        .font(.caption)
                }
                if d.name == nil && d.assetDescription == nil && d.homepage == nil {
                    Text("No extra info for this asset.").font(.caption).foregroundColor(.secondary)
                }
            } else {
                Text("Name, description, and link from CoinGecko when market data is loaded.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }
}

// MARK: - Dashboard tab (cards + per-asset table + refresh)

struct DashboardTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var projectionEditIndex: Int?
    @State private var projectionEditRow: [String] = []
    @State private var cryptoNewsItems: [(title: String, link: String)] = []
    @State private var cryptoNewsLoading = false
    @State private var economicNewsItems: [(title: String, link: String)] = []
    @State private var economicNewsLoading = false
    @State private var fearGreedValue: Int? = nil
    @State private var fearGreedClassification: String? = nil
    /// Incremented to re-run news + Fear & Greed load (pull-to-refresh or Refresh button).
    @State private var newsSentimentRefreshId = 0
    /// When non-nil and non-empty, correlation heatmap is shown; otherwise placeholder.
    @State private var correlationMatrix: CorrelationMatrix? = nil

    private var totalFees: Double {
        appState.filteredTrades().reduce(0) { $0 + $1.fee }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if appState.isLoading {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("Refreshing prices…").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(8)
                }
                Button("Refresh prices") { Task { await appState.refreshPrices() } }
                    .disabled(appState.isLoading)
                if let m = appState.portfolioMetrics {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 12) {
                        dashboardCard(title: "Portfolio value", value: m.total_value, format: .currency)
                        dashboardCard(title: "Capital in", value: m.total_external_cash, format: .currency)
                        dashboardCard(title: "Total P&L", value: m.total_pnl, format: .currency, colorize: true)
                        dashboardCard(title: "ROI", value: m.roi_pct, format: .percent, colorize: true)
                        dashboardCard(title: "Realized P&L", value: m.realized_pnl, format: .currency, colorize: true)
                        dashboardCard(title: "Unrealized P&L", value: m.unrealized_pnl, format: .currency, colorize: true)
                        dashboardCard(title: "USD cash", value: m.usd_balance, format: .currency)
                        dashboardCard(title: "Cost basis", value: m.total_cost_basis_assets, format: .currency)
                        dashboardCard(title: "Total fees", value: totalFees, format: .currency)
                        if let p24 = appState.portfolio24hUsd() {
                            dashboardCard(title: "Portfolio 24h", value: p24, format: .currency, colorize: true)
                        }
                    }
                    .padding(.horizontal)
                    if let a = appState.tradingAnalytics {
                        Divider()
                        Text("Trading analytics").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                            dashboardCard(title: "Max drawdown", value: a.max_drawdown, format: .currency, tooltip: "Largest peak-to-trough decline.")
                            dashboardCard(title: "Max drawdown %", value: a.max_drawdown_pct, format: .percent, tooltip: "As % of peak.")
                            if let sharpe = a.sharpe_ratio {
                                dashboardCard(title: "Sharpe ratio", value: sharpe, format: .plain(2), tooltip: "Risk-adjusted return.")
                            }
                            if let sortino = a.sortino_ratio {
                                dashboardCard(title: "Sortino ratio", value: sortino, format: .plain(2), tooltip: "Downside risk-adjusted return.")
                            }
                            if let wr = a.win_rate_pct {
                                dashboardCard(title: "Win rate", value: wr, format: .percent1, tooltip: "% of profitable trades.")
                            }
                            if let rv = a.realized_volatility {
                                dashboardCard(title: "Realized vol", value: rv, format: .plain(4), tooltip: "Std dev of period returns.")
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Trades").font(.caption).foregroundColor(.secondary)
                                Text("\(a.total_trades)").font(.title2).fontWeight(.semibold)
                                Text("\(a.winning_trades) W / \(a.losing_trades) L").font(.caption2).foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    Divider()
                    Text("Per-asset breakdown").font(.headline)
                    dashboardAssetTable(metrics: m)
                    Divider()
                    Text("Client P&L Summary").font(.headline)
                    clientPnlSummaryTable
                    Divider()
                    Text("Benchmark vs BTC").font(.headline)
                    benchmarkSection
                    Divider()
                    Text("Scenario / What-if").font(.headline)
                    scenarioSection
                    Divider()
                    Text("Correlation (returns)").font(.headline)
                    correlationSection
                    Divider()
                    HStack {
                        Text("Fear & Greed Index").font(.headline)
                        Spacer()
                        Button("Refresh") { newsSentimentRefreshId += 1 }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    fearGreedSection
                    Divider()
                    Text("Crypto news (Bitcoin-centered)").font(.headline)
                    cryptoNewsSection
                    Divider()
                    Text("Economic & financial news").font(.headline)
                    economicNewsSection
                    Divider()
                    Text("Noteworthy news (crypto impact)").font(.headline)
                    noteworthyNewsSection
                    Divider()
                    Text("Tax lots").font(.headline)
                    taxLotSection
                    Divider()
                    Text("Tax export (by year)").font(.headline)
                    taxExportSection
                    Divider()
                    Text("Projections & Pro forma").font(.headline)
                    projectionsSection
                    Divider()
                    recentAPIActivitySection
                    triggeredAlertsSection
                    Divider()
                    Text("Activity Log").font(.headline)
                    activityLogSection
                } else {
                    Text("No metrics").padding()
                }
            }
            .padding()
        }
        .refreshable {
            newsSentimentRefreshId += 1
        }
        .task(id: newsSentimentRefreshId) {
            async let c: () = loadCryptoNews()
            async let e: () = loadEconomicNews()
            async let f: () = loadFearGreed()
            async let corr: CorrelationMatrix? = appState.loadCorrelationMatrix()
            _ = await (c, e, f)
            appState.checkAndNotifyNoteworthyNews(items: noteworthyFilteredItems())
            correlationMatrix = await corr
        }
    }

    @State private var scenarioAsset = "BTC"
    @State private var scenarioPct = "-20"
    @State private var taxExportYear = Calendar.current.component(.year, from: Date())
    @State private var benchmarkBTCHold: Double?
    @State private var benchmarkLoading = false

    private var benchmarkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let btcEnd = benchmarkBTCHold, let total = appState.portfolioMetrics?.total_value {
                Text("Same start capital: Portfolio now \(formatCurrency(total)); 100% BTC hold would be \(formatCurrency(btcEnd)).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Compare portfolio vs 100% BTC from first funding date.").font(.caption).foregroundColor(.secondary)
            }
            Button(benchmarkLoading ? "Loading…" : "Load benchmark vs BTC") {
                benchmarkLoading = true
                Task {
                    let (_, btc) = await appState.benchmarkBTCSeries()
                    await MainActor.run {
                        benchmarkBTCHold = btc?.last?.value
                        benchmarkLoading = false
                    }
                }
            }
            .disabled(benchmarkLoading)
            .buttonStyle(.bordered)
        }
        .padding(8)
    }

    private var scenarioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                TextField("Asset", text: $scenarioAsset).textFieldStyle(.roundedBorder).frame(width: 80)
                TextField("% change", text: $scenarioPct).textFieldStyle(.roundedBorder).frame(width: 60)
                Text("e.g. -20 for -20%").font(.caption).foregroundColor(.secondary)
            }
            let pct = (Double(scenarioPct) ?? 0) / 100.0
            let mult = 1.0 + pct
            let shocks = [scenarioAsset.uppercased(): mult]
            let (newVal, delta) = appState.scenarioPortfolioValue(shocks: shocks)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("If \(scenarioAsset) goes \(scenarioPct)%: New value ")
                    .font(.caption)
                Text(formatCurrency(newVal)).font(.caption).fontWeight(.medium)
                Text("; Δ ")
                    .font(.caption)
                Text(formatCurrency(delta)).font(.caption).foregroundColor(delta >= 0 ? .green : .red)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(8)
        }
        .padding(8)
    }

    /// Pairwise return correlation: heatmap when data exists, otherwise placeholder.
    private var correlationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cm = correlationMatrix, !cm.assets.isEmpty {
                correlationHeatmapView(assets: cm.assets, matrix: cm.matrix)
            } else {
                Text("Pairwise correlation of returns for held assets (heatmap). Historical per-asset price data is required; when available, the matrix will appear here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Coming in a future release.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    /// Simple N×N heatmap: -1 (red) → 0 (gray) → 1 (green). First row/column are asset labels.
    private func correlationHeatmapView(assets: [String], matrix: [[Double]]) -> some View {
        let cellSize: CGFloat = 28
        return VStack(alignment: .leading, spacing: 2) {
            Text("Pearson correlation of daily returns. Diagonal = 1. From stored price history (refresh on 2+ days for more history).")
                .font(.caption2)
                .foregroundColor(.secondary)
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 2) {
                    // Header row: empty + asset labels
                    HStack(spacing: 2) {
                        Color.clear.frame(width: cellSize, height: cellSize)
                        ForEach(assets, id: \.self) { a in
                            Text(a)
                                .font(.system(size: 9, weight: .medium))
                                .frame(width: cellSize, height: cellSize)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    ForEach(Array(assets.enumerated()), id: \.offset) { i, rowAsset in
                        HStack(spacing: 2) {
                            Text(rowAsset)
                                .font(.system(size: 9, weight: .medium))
                                .frame(width: cellSize, height: cellSize)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            ForEach(Array(assets.enumerated()), id: \.offset) { j, _ in
                                let val = i < matrix.count && j < matrix[i].count ? matrix[i][j] : 0
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(correlationColor(val))
                                    .frame(width: cellSize, height: cellSize)
                                    .overlay(Text(String(format: "%.2f", val)).font(.system(size: 8)).foregroundColor(val >= -0.5 && val <= 0.5 ? .primary : .white))
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    /// Heatmap color: -1 → red, 0 → gray, 1 → green.
    private func correlationColor(_ value: Double) -> Color {
        let t = max(0, min(1, (value + 1) / 2))
        if t <= 0.5 {
            let s = t * 2
            return Color(red: 1, green: s, blue: s)
        } else {
            let s = (t - 0.5) * 2
            return Color(red: 1 - s, green: 1, blue: 1 - s)
        }
    }

    /// Fear & Greed Index (0–100) from alternative.me; Extreme Fear → Extreme Greed.
    private var fearGreedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let value = fearGreedValue, let classification = fearGreedClassification {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(value)")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(fearGreedColor(value: value))
                    Text(classification)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Text("Source: alternative.me (crypto market sentiment). 0 = Extreme Fear, 100 = Extreme Greed.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("Crypto Fear & Greed Index (alternative.me). Loading…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private func fearGreedColor(value: Int) -> Color {
        switch value {
        case 0..<25: return .red
        case 25..<45: return .orange
        case 45..<55: return .secondary
        case 55..<75: return .green.opacity(0.9)
        default: return .green
        }
    }

    private func loadFearGreed() async {
        let url = URL(string: "https://api.alternative.me/fng/?limit=1")!
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArr = json["data"] as? [[String: Any]],
                  let first = dataArr.first,
                  let valueStr = first["value"] as? String,
                  let value = Int(valueStr),
                  let classification = first["value_classification"] as? String else {
                await MainActor.run { fearGreedValue = nil; fearGreedClassification = nil }
                return
            }
            await MainActor.run {
                fearGreedValue = value
                fearGreedClassification = classification
            }
        } catch {
            await MainActor.run { fearGreedValue = nil; fearGreedClassification = nil }
        }
    }

    /// Crypto news feed (CoinDesk RSS).
    private var cryptoNewsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if cryptoNewsLoading {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading crypto news…").font(.caption).foregroundColor(.secondary)
                }
                .padding(4)
            } else if cryptoNewsItems.isEmpty {
                Text("Crypto news (Bitcoin/crypto RSS). Feed could not be loaded or is empty.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(cryptoNewsItems.prefix(10).enumerated()), id: \.offset) { _, item in
                    if let url = URL(string: item.link), !item.title.isEmpty {
                        Link(destination: url) {
                            Text(item.title)
                                .font(.caption)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    /// Fetches CoinDesk RSS and parses items (title + link) for the crypto news section.
    private func loadCryptoNews() async {
        await MainActor.run { cryptoNewsLoading = true }
        let feedURL = URL(string: "https://www.coindesk.com/arc/outboundfeeds/rss/")!
        var items: [(title: String, link: String)] = []
        do {
            let (data, _) = try await URLSession.shared.data(from: feedURL)
            items = Self.parseRSSItems(data: data)
        } catch {
            items = []
        }
        await MainActor.run {
            cryptoNewsItems = items
            cryptoNewsLoading = false
        }
    }

    /// Parses RSS/XML data for <item> elements (under <channel>) and returns (title, link) pairs.
    private static func parseRSSItems(data: Data) -> [(title: String, link: String)] {
        var result: [(title: String, link: String)] = []
        guard let doc = try? XMLDocument(data: data, options: []),
              let root = doc.rootElement() else { return result }
        func textOfFirstChild(_ parent: XMLElement?, name: String) -> String? {
            guard let el = parent?.elements(forName: name).first else { return nil }
            return el.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let channel = root.elements(forName: "channel").first else { return result }
        let items = channel.elements(forName: "item")
        for el in items {
            guard let title = textOfFirstChild(el, name: "title"), !title.isEmpty,
                  let link = textOfFirstChild(el, name: "link") ?? textOfFirstChild(el, name: "guid"), !link.isEmpty else { continue }
            result.append((title: title, link: link))
        }
        return result
    }

    /// Placeholder: economic and financial news (government + private companies).
    private var economicNewsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if economicNewsLoading {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading economic news…").font(.caption).foregroundColor(.secondary)
                }
                .padding(4)
            } else if economicNewsItems.isEmpty {
                Text("Economic and financial news (e.g. BBC Business). Feed could not be loaded or is empty.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(economicNewsItems.prefix(8).enumerated()), id: \.offset) { _, item in
                    if let url = URL(string: item.link), !item.title.isEmpty {
                        Link(destination: url) {
                            Text(item.title)
                                .font(.caption)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    /// Noteworthy: items from crypto + economic feeds whose title matches macro/crypto-impact keywords.
    private var noteworthyNewsSection: some View {
        let noteworthy = noteworthyFilteredItems()
        return VStack(alignment: .leading, spacing: 8) {
            Text("Filtered for Fed, rates, regulation, crypto, inflation. From crypto and economic feeds above.")
                .font(.caption2)
                .foregroundColor(.secondary)
            if noteworthy.isEmpty && !cryptoNewsLoading && !economicNewsLoading {
                Text("No matching headlines. Keywords: Fed, rate, SEC, crypto, Bitcoin, inflation, regulation, bank.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(noteworthy.prefix(8).enumerated()), id: \.offset) { _, item in
                    if let url = URL(string: item.link), !item.title.isEmpty {
                        Link(destination: url) {
                            Text(item.title)
                                .font(.caption)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private static let noteworthyKeywords = ["fed", "rate", "sec", "crypto", "bitcoin", "inflation", "regulation", "interest", "bank", "etf", "macro", "cut", "hike"]

    private func noteworthyFilteredItems() -> [(title: String, link: String)] {
        let combined = (cryptoNewsItems + economicNewsItems)
        let lowercased = combined.map { (title: $0.title.lowercased(), link: $0.link) }
        return zip(combined, lowercased)
            .filter { _, lower in Self.noteworthyKeywords.contains { lower.title.contains($0) } }
            .map(\.0)
    }

    private func loadEconomicNews() async {
        await MainActor.run { economicNewsLoading = true }
        let feedURL = URL(string: "https://feeds.bbci.co.uk/news/business/rss.xml")!
        var items: [(title: String, link: String)] = []
        do {
            let (data, _) = try await URLSession.shared.data(from: feedURL)
            items = Self.parseRSSItems(data: data)
        } catch {
            items = []
        }
        await MainActor.run {
            economicNewsItems = items
            economicNewsLoading = false
        }
    }

    private var taxLotSection: some View {
        let rows = appState.taxLotRows()
        return VStack(alignment: .leading, spacing: 8) {
            if rows.isEmpty {
                Text("No open lots (or no positions).").font(.caption).foregroundColor(.secondary).padding(8)
            } else {
                HStack(spacing: 8) {
                    Text("Asset").frame(width: 52, alignment: .leading).font(.caption).foregroundColor(.secondary)
                    Text("Qty").frame(width: 72, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                    Text("Cost/unit").frame(width: 80, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                    Text("Acquisition date").frame(width: 140, alignment: .leading).font(.caption).foregroundColor(.secondary)
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 8) {
                        Text(r.asset).frame(width: 52, alignment: .leading).font(.caption)
                        Text(String(format: "%.4f", r.qty)).frame(width: 72, alignment: .trailing).font(.caption)
                        Text(String(format: "%.2f", r.costPerUnit)).frame(width: 80, alignment: .trailing).font(.caption)
                        Text(String(r.date.prefix(19))).frame(width: 140, alignment: .leading).font(.caption).lineLimit(1)
                    }
                }
                Button("Export tax lots CSV") {
                    let header = "Asset,Qty,Cost Per Unit,Acquisition Date\n"
                    let body = rows.map { "\($0.asset),\($0.qty),\($0.costPerUnit),\($0.date)" }.joined(separator: "\n")
                    let csv = header + body
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.commaSeparatedText]
                    panel.nameFieldStringValue = "tax_lots_\(taxExportYear).csv"
                    if panel.runModal() == .OK, let url = panel.url {
                        try? csv.write(to: url, atomically: true, encoding: .utf8)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private var taxExportSection: some View {
        HStack(spacing: 12) {
            Picker("Year", selection: $taxExportYear) {
                ForEach((2020...2030).reversed(), id: \.self) { y in
                    Text(String(y)).tag(y)
                }
            }
            .frame(width: 100)
            Button("Export trades CSV for tax") {
                let csv = appState.exportTradesForYearCSV(year: taxExportYear)
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.commaSeparatedText]
                panel.nameFieldStringValue = "trades_\(taxExportYear).csv"
                if panel.runModal() == .OK, let url = panel.url {
                    try? csv.write(to: url, atomically: true, encoding: .utf8)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(8)
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private var clientPnlSummaryTable: some View {
        let rows = appState.clientPnlRows()
        return VStack(alignment: .leading, spacing: 6) {
            if rows.isEmpty {
                Text("No client users, or enable \"I am a client\" for users to see their row here.")
                    .font(.caption).foregroundColor(.secondary)
                    .padding(8)
            } else {
                HStack(spacing: 12) {
                    Text("Client").frame(width: 100, alignment: .leading).font(.caption).foregroundColor(.secondary)
                    Text("Your %").frame(width: 64, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                    Text("Client P&L").frame(width: 88, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                    Text("Your Share").frame(width: 88, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                }
                ForEach(rows, id: \.clientName) { row in
                    HStack(spacing: 12) {
                        Text(row.clientName).frame(width: 100, alignment: .leading).font(.caption)
                        AnimatedNumberText(value: row.yourPct, format: .percent1, font: .caption)
                            .frame(width: 64, alignment: .trailing)
                        AnimatedNumberText(value: row.clientPnl, format: .currency, color: row.clientPnl >= 0 ? .green : .red, font: .caption)
                            .frame(width: 88, alignment: .trailing)
                        AnimatedNumberText(value: row.yourShare, format: .currency, color: row.yourShare >= 0 ? .green : .red, font: .caption)
                            .frame(width: 88, alignment: .trailing)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    /// Projection row normalized to 6 columns: Asset, Type, Price ($), Qty, Amount ($), Account.
    private static let projectionColumnCount = 6
    private static let projectionHeaders = ["Asset", "Type", "Price ($)", "Qty", "Amount ($)", "Account"]

    private var projectionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Add row") {
                    appState.addProjectionRow(Array(repeating: "", count: Self.projectionColumnCount))
                }
                Spacer()
            }
            HStack(spacing: 8) {
                ForEach(Self.projectionHeaders, id: \.self) { h in
                    Text(h).font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            ForEach(Array(appState.projectionsRows.enumerated()), id: \.offset) { index, row in
                let normalized = row.count >= Self.projectionColumnCount ? Array(row.prefix(Self.projectionColumnCount)) : row + Array(repeating: "", count: max(0, Self.projectionColumnCount - row.count))
                HStack(spacing: 8) {
                    ForEach(Array(normalized.enumerated()), id: \.offset) { colIdx, val in
                        Text(val).font(.caption).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                    }
                    Spacer()
                }
                .padding(4)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(4)
                .contextMenu {
                    Button("Edit row…") {
                        projectionEditIndex = index
                        projectionEditRow = normalized
                    }
                    Button("Delete", role: .destructive) { appState.removeProjectionRow(at: index) }
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(8)
        .sheet(isPresented: Binding(get: { projectionEditIndex != nil }, set: { if !$0 { projectionEditIndex = nil } })) {
            if let idx = projectionEditIndex {
                EditProjectionSheet(row: projectionEditRow, onDismiss: { projectionEditIndex = nil }, onSave: { newRow in
                    appState.updateProjectionRow(at: idx, newRow)
                    projectionEditIndex = nil
                })
            }
        }
    }

    /// Recent trades that came from the API (e.g. Crank) with source or strategy_id set.
    /// Triggered alerts block: use a standalone View with explicit params to avoid EnvironmentObject type issues.
    private var triggeredAlertsSection: some View {
        TriggeredAlertsSectionView(
            alerts: appState.triggeredAlerts,
            onDismiss: { appState.dismissTriggeredAlerts() }
        )
    }

    private var recentAPIActivitySection: some View {
        let trades = appState.recentAPIOriginTrades(limit: 10)
        return Group {
            Text("Recent API activity").font(.headline)
            if trades.isEmpty {
                Text("No API-originated trades yet. Trades posted to POST /v1/trades with source or strategy_id will appear here.")
                    .font(.caption).foregroundColor(.secondary)
                    .padding(8)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Date").frame(width: 140, alignment: .leading).font(.caption).foregroundColor(.secondary)
                        Text("Asset").frame(width: 48, alignment: .leading).font(.caption).foregroundColor(.secondary)
                        Text("Type").frame(width: 44, alignment: .leading).font(.caption).foregroundColor(.secondary)
                        Text("Qty").frame(width: 64, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                        Text("Source").frame(width: 60, alignment: .leading).font(.caption).foregroundColor(.secondary)
                        Text("Strategy").frame(width: 100, alignment: .leading).font(.caption).foregroundColor(.secondary)
                    }
                    ForEach(trades, id: \.id) { t in
                        HStack(spacing: 8) {
                            Text(String(t.date.prefix(19))).font(.system(.caption, design: .monospaced)).frame(width: 140, alignment: .leading).lineLimit(1)
                            Text(t.asset).font(.caption).frame(width: 48, alignment: .leading)
                            Text(t.type).font(.caption).frame(width: 44, alignment: .leading)
                            Text(String(format: "%.4f", t.quantity)).font(.caption).frame(width: 64, alignment: .trailing)
                            Text(t.source ?? "—").font(.caption).frame(width: 60, alignment: .leading).lineLimit(1)
                            Text(t.strategy_id ?? "—").font(.caption).frame(width: 100, alignment: .leading).lineLimit(1)
                        }
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(8)
            }
        }
    }

    private var activityLogSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(appState.activityLog.enumerated().reversed()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(height: 120)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(8)
        }
    }

    private func dashboardAssetTable(metrics: PortfolioMetrics) -> some View {
        let sortedAssets = metrics.per_asset.keys.sorted()
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text("Asset").frame(width: 52, alignment: .leading).font(.caption).foregroundColor(.secondary)
                Text("Qty").frame(width: 72, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                Text("Avg cost").frame(width: 72, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                Text("Price").frame(width: 72, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                Text("Value").frame(width: 72, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                Text("Realized").frame(width: 64, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                Text("Unrealized").frame(width: 64, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                Text("Lifetime").frame(width: 64, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                Text("24h %").frame(width: 52, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                Text("ROI %").frame(width: 52, alignment: .trailing).font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 4)
            ForEach(sortedAssets, id: \.self) { asset in
                if let pa = metrics.per_asset[asset] {
                    let qty = pa.units_held + pa.holding_qty
                    let avgCost = qty > 0 ? pa.cost_basis / qty : 0
                    let pct24h = appState.pctChange24h(asset: asset)
                    HStack(alignment: .center, spacing: 8) {
                        Text(asset).frame(width: 52, alignment: .leading).font(.caption)
                        AnimatedNumberText(value: qty, format: .plain(4), font: .caption).frame(width: 72, alignment: .trailing)
                        AnimatedNumberText(value: avgCost, format: .currency, font: .caption).frame(width: 72, alignment: .trailing)
                        AnimatedNumberText(value: pa.price ?? 0, format: .currency, font: .caption).frame(width: 72, alignment: .trailing)
                        AnimatedNumberText(value: pa.current_value, format: .currency, font: .caption).frame(width: 72, alignment: .trailing)
                        AnimatedNumberText(value: pa.realized_pnl, format: .currency, color: pa.realized_pnl >= 0 ? .green : .red, font: .caption).frame(width: 64, alignment: .trailing)
                        AnimatedNumberText(value: pa.unrealized_pnl, format: .currency, color: pa.unrealized_pnl >= 0 ? .green : .red, font: .caption).frame(width: 64, alignment: .trailing)
                        AnimatedNumberText(value: pa.lifetime_pnl, format: .currency, color: pa.lifetime_pnl >= 0 ? .green : .red, font: .caption).frame(width: 64, alignment: .trailing)
                        Group {
                            if let pct = pct24h {
                                AnimatedNumberText(value: pct, format: .percentSigned, color: pct >= 0 ? .green : .red, font: .caption)
                            } else {
                                Text("—").font(.caption).foregroundColor(.secondary)
                            }
                        }.frame(width: 52, alignment: .trailing)
                        AnimatedNumberText(value: pa.roi_pct, format: .percent1, color: pa.roi_pct >= 0 ? .green : .red, font: .caption).frame(width: 52, alignment: .trailing)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private enum DashFormat { case currency; case percent; case percent1; case plain(Int) }
    private func dashboardCard(title: String, value: Double, format: DashFormat, colorize: Bool = false, tooltip: String? = nil) -> some View {
        let color: Color? = colorize ? (value >= 0 ? .green : .red) : nil
        let animFormat: AnimatedNumberFormat = {
            switch format {
            case .currency: return .currency
            case .percent: return .percent
            case .percent1: return .percent1
            case .plain(let d): return .plain(d)
            }
        }()
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
                .help(tooltip ?? title)
            AnimatedNumberText(value: value, format: animFormat, color: color, font: .title2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(12)
    }
}

// MARK: - PnL Chart tab (Swift Charts)

enum ChartPeriod: String, CaseIterable {
    case d1 = "1D"
    case w1 = "1W"
    case m1 = "1M"
    case m3 = "3M"
    case m6 = "6M"
    case y1 = "1Y"
    case all = "All"
}

struct PnLChartTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var chartAsset: String = "All"
    @State private var chartPeriod: ChartPeriod = .all
    @State private var valueInUsd: Bool = true
    @State private var periodAggregation: String = "month" // "month" or "quarter" for monthly/quarterly P&L chart
    /// Persisted per-chart period overrides (e.g. "cumulative_pnl=1M,drawdown=3M"); survives app restart.
    @AppStorage("chartPeriodOverrides") private var chartPeriodOverridesRaw: String = ""
    /// Persisted per-chart aggregation overrides (e.g. "monthly_quarterly_pnl=quarter"); survives app restart.
    @AppStorage("periodAggregationOverrides") private var periodAggregationOverridesRaw: String = ""

    /// Parsed period overrides from persisted string; key missing means use global chartPeriod.
    private var chartPeriodOverrides: [String: ChartPeriod] {
        var result: [String: ChartPeriod] = [:]
        for part in chartPeriodOverridesRaw.split(separator: ",") {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let key = String(pair[0]).trimmingCharacters(in: .whitespaces)
            let raw = String(pair[1]).trimmingCharacters(in: .whitespaces)
            if let period = ChartPeriod(rawValue: raw) { result[key] = period }
        }
        return result
    }

    /// Serialize period overrides for persistence.
    private func serializePeriodOverrides(_ next: [String: ChartPeriod]) -> String {
        next.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value.rawValue)" }.joined(separator: ",")
    }

    /// Parsed aggregation overrides from persisted string.
    private var periodAggregationOverrides: [String: String] {
        var result: [String: String] = [:]
        for part in periodAggregationOverridesRaw.split(separator: ",") {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let key = String(pair[0]).trimmingCharacters(in: .whitespaces)
            let val = String(pair[1]).trimmingCharacters(in: .whitespaces)
            if val == "month" || val == "quarter" { result[key] = val }
        }
        return result
    }

    /// Serialize aggregation overrides for persistence.
    private func serializeAggregationOverrides(_ next: [String: String]) -> String {
        next.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    /// Chart IDs that use time-range period (1D, 1W, 1M, …).
    private static let periodChartIds = [
        "cumulative_pnl", "equity_curve", "drawdown", "trade_volume", "fees_over_time",
        "deposits_withdrawals", "trade_frequency", "net_flow", "rolling_sharpe"
    ]
    /// Chart IDs that use month/quarter aggregation.
    private static let aggregationChartIds = ["monthly_quarterly_pnl"]

    private var chartTrades: [Trade] {
        var list = appState.filteredTrades()
        if chartAsset != "All" {
            list = list.filter { $0.asset == chartAsset }
        }
        return list
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Effective period for a chart (per-chart override or global).
    private func effectivePeriod(for chartId: String) -> ChartPeriod {
        chartPeriodOverrides[chartId] ?? chartPeriod
    }

    /// Effective aggregation for a chart (per-chart override or global).
    private func effectiveAggregation(for chartId: String) -> String {
        periodAggregationOverrides[chartId] ?? periodAggregation
    }

    /// Binding for a chart’s period; updates persisted overrides and triggers view refresh.
    private func periodBinding(for chartId: String) -> Binding<ChartPeriod> {
        Binding(
            get: { effectivePeriod(for: chartId) },
            set: { newValue in
                var next = chartPeriodOverrides
                next[chartId] = newValue
                chartPeriodOverridesRaw = serializePeriodOverrides(next)
            }
        )
    }

    /// Binding for a chart’s month/quarter aggregation; updates persisted overrides.
    private func aggregationBinding(for chartId: String) -> Binding<String> {
        Binding(
            get: { effectiveAggregation(for: chartId) },
            set: { newValue in
                var next = periodAggregationOverrides
                next[chartId] = newValue
                periodAggregationOverridesRaw = serializeAggregationOverrides(next)
            }
        )
    }

    /// Filters time-series points by the given period (based on last point date).
    private func filterPointsByPeriod(_ points: [(date: String, value: Double)], period: ChartPeriod) -> [(date: String, value: Double)] {
        guard !points.isEmpty else { return points }
        let endDate = points.last.flatMap { Self.dateFormatter.date(from: $0.date) } ?? Date()
        let startDate: Date
        switch period {
        case .d1: startDate = Calendar.current.date(byAdding: .day, value: -1, to: endDate) ?? endDate
        case .w1: startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate) ?? endDate
        case .m1: startDate = Calendar.current.date(byAdding: .month, value: -1, to: endDate) ?? endDate
        case .m3: startDate = Calendar.current.date(byAdding: .month, value: -3, to: endDate) ?? endDate
        case .m6: startDate = Calendar.current.date(byAdding: .month, value: -6, to: endDate) ?? endDate
        case .y1: startDate = Calendar.current.date(byAdding: .year, value: -1, to: endDate) ?? endDate
        case .all: startDate = Date.distantPast
        }
        return points.filter { guard let d = Self.dateFormatter.date(from: $0.date) else { return false }; return d >= startDate }
    }

    private func chartPointsCumulativeRealized(period: ChartPeriod) -> [(date: String, value: Double)] {
        let series = MetricsService().cumulativeRealizedPnlSeries(
            trades: chartTrades,
            costBasisMethod: appState.data.settings.cost_basis_method
        )
        var points = series.map { (date: $0.date, value: $0.value) }
        points = filterPointsByPeriod(points, period: period)
        if !valueInUsd {
            let price: Double? = chartAsset != "All"
                ? appState.currentPrice(asset: chartAsset)
                : appState.btcPrice()
            if let p = price, p > 0 {
                points = points.map { ($0.date, $0.value / p) }
            }
        }
        return points
    }

    private var assetChoices: [String] {
        let set = Set(appState.filteredTrades().map(\.asset)).filter { $0 != "USD" }
        return ["All"] + set.sorted()
    }

    private var yAxisLabelCumulativeRealized: String {
        if valueInUsd { return "Cumulative realized P&L ($)" }
        return chartAsset != "All" ? "Cumulative realized P&L (\(chartAsset))" : "Cumulative realized P&L (BTC)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Global filters: asset and value unit (period/aggregation are per-chart, inline with titles)
                HStack(spacing: 16) {
                    Picker("Asset", selection: $chartAsset) {
                        ForEach(assetChoices, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(width: 100)
                    Toggle("Value in USD", isOn: $valueInUsd).toggleStyle(.checkbox)
                }
                .padding(.bottom, 8)

                // All charts in order of relevancy and usefulness
                chartSection("Cumulative realized P&L over time", control: {
                    Picker("Period", selection: periodBinding(for: "cumulative_pnl")) {
                        ForEach(ChartPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 100)
                }) {
                    let points = chartPointsCumulativeRealized(period: effectivePeriod(for: "cumulative_pnl"))
                    if points.isEmpty {
                        emptyMessage(chartAsset != "All" ? "No sells for this asset" : "No trade data for chart")
                    } else {
                        ChartView(points: points, yAxisLabel: yAxisLabelCumulativeRealized)
                            .frame(height: 260)
                    }
                }

                chartSection("Equity curve", control: {
                    Picker("Period", selection: periodBinding(for: "equity_curve")) {
                        ForEach(ChartPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 100)
                }) {
                    let totalValue = appState.portfolioMetrics?.total_value ?? 0
                    let curve = MetricsService().equityCurveSeries(
                        trades: chartTrades,
                        costBasisMethod: appState.data.settings.cost_basis_method,
                        currentTotalValue: totalValue
                    )
                    let points = filterPointsByPeriod(curve, period: effectivePeriod(for: "equity_curve"))
                    if points.isEmpty {
                        emptyMessage("No trade data for equity curve")
                    } else {
                        ChartView(points: points, yAxisLabel: "Portfolio value ($)")
                            .frame(height: 260)
                    }
                }

                chartSection("Drawdown over time", control: {
                    Picker("Period", selection: periodBinding(for: "drawdown")) {
                        ForEach(ChartPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 100)
                }) {
                    let totalValue = appState.portfolioMetrics?.total_value ?? 0
                    let curve = MetricsService().equityCurveSeries(
                        trades: chartTrades,
                        costBasisMethod: appState.data.settings.cost_basis_method,
                        currentTotalValue: totalValue
                    )
                    let ddPoints = MetricsService().drawdownSeries(fromEquityCurve: curve)
                    let points = filterPointsByPeriod(ddPoints, period: effectivePeriod(for: "drawdown"))
                    if points.isEmpty {
                        emptyMessage("No trade data for drawdown")
                    } else {
                        ChartView(points: points, yAxisLabel: "Drawdown ($)")
                            .frame(height: 260)
                    }
                }

                // Portfolio snapshot row: compact charts that don't need full width
                chartSection("Portfolio overview") {
                    HStack(alignment: .top, spacing: 16) {
                        inlineChartColumn("Asset allocation") {
                            assetAllocationChart
                        }
                        inlineChartColumn("Realized P&L by asset") {
                            realizedPnlByAssetChart
                        }
                        inlineChartColumn("Cost vs value by asset") {
                            costVsValueChart
                        }
                        inlineChartColumn("ROI % by asset") {
                            roiByAssetChart
                        }
                    }
                }

                chartSection("Trade volume over time", control: {
                    Picker("Period", selection: periodBinding(for: "trade_volume")) {
                        ForEach(ChartPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 100)
                }) {
                    tradeVolumeChart(period: effectivePeriod(for: "trade_volume"))
                }

                chartSection("Monthly / quarterly realized P&L", control: {
                    Picker("Aggregation", selection: aggregationBinding(for: "monthly_quarterly_pnl")) {
                        Text("Monthly").tag("month")
                        Text("Quarterly").tag("quarter")
                    }
                    .frame(width: 110)
                    .controlSize(.small)
                }) {
                    monthlyQuarterlyPnlChart(aggregation: effectiveAggregation(for: "monthly_quarterly_pnl"))
                }

                chartSection("Fees over time", control: {
                    Picker("Period", selection: periodBinding(for: "fees_over_time")) {
                        ForEach(ChartPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 100)
                }) {
                    feesOverTimeChart(period: effectivePeriod(for: "fees_over_time"))
                }

                chartSection("Win/loss distribution") {
                    winLossDistributionChart
                }

                chartSection("Largest wins and losses") {
                    largestWinsLossesChart
                }

                // Additional charts
                chartSection("Realized P&L by exchange") {
                    realizedPnlByExchangeChart
                }

                chartSection("Fees by exchange") {
                    feesByExchangeChart
                }

                chartSection("Trade volume by exchange") {
                    tradeVolumeByExchangeChart
                }

                chartSection("Deposits & withdrawals over time", control: {
                    Picker("Period", selection: periodBinding(for: "deposits_withdrawals")) {
                        ForEach(ChartPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 100)
                }) {
                    depositsWithdrawalsChart(period: effectivePeriod(for: "deposits_withdrawals"))
                }

                chartSection("Largest trades by size") {
                    largestTradesBySizeChart
                }

                chartSection("Profit factor") {
                    profitFactorChartWithBars
                }

                chartSection("Trade size distribution") {
                    tradeSizeDistributionChart
                }

                chartSection("Trade frequency over time", control: {
                    Picker("Period", selection: periodBinding(for: "trade_frequency")) {
                        ForEach(ChartPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 100)
                }) {
                    tradeFrequencyChart(period: effectivePeriod(for: "trade_frequency"))
                }

                chartSection("Net flow by period", control: {
                    Picker("Period", selection: periodBinding(for: "net_flow")) {
                        ForEach(ChartPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 100)
                }) {
                    netFlowChart(period: effectivePeriod(for: "net_flow"))
                }

                chartSection("Realized vs unrealized (current)") {
                    realizedVsUnrealizedChart
                }

                chartSection("Average hold time distribution") {
                    holdTimeDistributionChart
                }

                chartSection("Rolling Sharpe ratio", control: {
                    Picker("Period", selection: periodBinding(for: "rolling_sharpe")) {
                        ForEach(ChartPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 100)
                }) {
                    rollingSharpeChart(period: effectivePeriod(for: "rolling_sharpe"))
                }
            }
            .padding()
        }
    }

    /// Wraps a chart in a titled section (relevancy-ordered list).
    private func chartSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    /// Chart section with an inline, right-aligned period/aggregation control next to the title.
    private func chartSection<Control: View, Content: View>(
        _ title: String,
        @ViewBuilder control: () -> Control,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer(minLength: 8)
                control()
            }
            content()
        }
    }

    /// Column for inline snapshot charts (e.g. in the portfolio overview row); shares width with siblings.
    private func inlineChartColumn<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text).foregroundColor(.secondary).padding()
    }

    // MARK: - Chart 4: Asset allocation (pie on macOS 14+, bar on 13)
    @ViewBuilder
    private var assetAllocationChart: some View {
        if let perAsset = appState.portfolioMetrics?.per_asset {
            let items = perAsset.filter { $0.key != "USD" && $0.value.current_value > 0 }
                .map { (asset: $0.key, value: $0.value.current_value) }
                .sorted { $0.value > $1.value }
            if items.isEmpty {
                emptyMessage("No assets to display")
            } else {
                let identifiable = items.map { AssetValueItem(asset: $0.asset, value: $0.value) }
                Group {
                    if #available(macOS 14.0, *) {
                        Chart(identifiable) { item in
                            SectorMark(
                                angle: .value("Value", item.value),
                                innerRadius: .ratio(0.5),
                                angularInset: 1
                            )
                            .foregroundStyle(by: .value("Asset", item.asset))
                        }
                        .chartLegend(position: .bottom)
                    } else {
                        Chart(identifiable) { item in
                            BarMark(x: .value("Asset", item.asset), y: .value("Value", item.value))
                                .foregroundStyle(by: .value("Asset", item.asset))
                        }
                        .chartLegend(position: .bottom)
                    }
                }
                .frame(height: 300)
                .padding()
            }
        } else {
            emptyMessage("No portfolio data")
        }
    }

    // MARK: - Chart 5: Realized P&L by asset (bar)
    @ViewBuilder
    private var realizedPnlByAssetChart: some View {
        if let perAsset = appState.portfolioMetrics?.per_asset {
            let items = perAsset.filter { $0.key != "USD" }
                .map { (asset: $0.key, value: $0.value.realized_pnl) }
                .filter { $0.value != 0 }
                .sorted { abs($0.value) > abs($1.value) }
            if items.isEmpty {
                emptyMessage("No realized P&L by asset")
            } else {
                BarChartSimpleView(items: items, valueLabel: "Realized P&L ($)")
                    .frame(height: 300)
                    .padding()
            }
        } else {
            emptyMessage("No portfolio data")
        }
    }

    // MARK: - Chart 6: Trade volume over time (grouped by period: buy vs sell)
    @ViewBuilder
    private func tradeVolumeChart(period: ChartPeriod) -> some View {
        let trades = chartTrades
        let points = Self.tradeVolumeByPeriod(trades: trades, period: period)
        if points.buy.isEmpty && points.sell.isEmpty {
            emptyMessage("No trade volume in period")
        } else {
            TradeVolumeChartView(buyPoints: points.buy, sellPoints: points.sell)
                .frame(height: 300)
                .padding()
        }
    }

    // MARK: - Chart 7: Fees over time (cumulative or per period)
    @ViewBuilder
    private func feesOverTimeChart(period: ChartPeriod) -> some View {
        let points = Self.feesSeries(trades: chartTrades, period: period)
        if points.isEmpty {
            emptyMessage("No fees in period")
        } else {
            ChartView(points: points, yAxisLabel: "Cumulative fees ($)")
                .frame(height: 300)
                .padding()
        }
    }

    // MARK: - Chart 8: Monthly / quarterly realized P&L
    @ViewBuilder
    private func monthlyQuarterlyPnlChart(aggregation: String) -> some View {
        let items = MetricsService().realizedPnlByPeriod(
            trades: chartTrades,
            costBasisMethod: appState.data.settings.cost_basis_method,
            period: aggregation
        )
        if items.isEmpty {
            emptyMessage("No realized P&L by period")
        } else {
            BarChartSimpleView(
                items: items.map { (asset: $0.periodLabel, value: $0.value) },
                valueLabel: "Realized P&L ($)"
            )
            .frame(height: 300)
            .padding()
        }
    }

    // MARK: - Chart 9: Win/loss distribution
    @ViewBuilder
    private var winLossDistributionChart: some View {
        let (wins, losses, winTotal, lossTotal) = Self.winLossAggregates(trades: chartTrades, appState: appState)
        if wins == 0 && losses == 0 {
            emptyMessage("No trades with P&L")
        } else {
            WinLossChartView(wins: wins, losses: losses, winTotal: winTotal, lossTotal: lossTotal)
                .frame(height: 280)
                .padding()
        }
    }

    // MARK: - Chart 10: Cost basis vs market value by asset
    @ViewBuilder
    private var costVsValueChart: some View {
        if let perAsset = appState.portfolioMetrics?.per_asset {
            let items = perAsset.filter { $0.key != "USD" }
                .map { (asset: $0.key, cost: $0.value.cost_basis, value: $0.value.current_value) }
                .filter { $0.cost > 0 || $0.value > 0 }
                .sorted { $0.value > $1.value }
            if items.isEmpty {
                emptyMessage("No assets to display")
            } else {
                CostVsValueChartView(items: items)
                    .frame(height: 300)
                    .padding()
            }
        } else {
            emptyMessage("No portfolio data")
        }
    }

    /// Stablecoin symbols excluded from ROI % chart (ROI is ~0% and not useful).
    private static let roiChartExcludedStablecoins: Set<String> = ["USD", "USDC", "USDT", "DAI", "BUSD", "TUSD", "USDP"]

    // MARK: - Chart 11: ROI % by asset
    @ViewBuilder
    private var roiByAssetChart: some View {
        if let perAsset = appState.portfolioMetrics?.per_asset {
            let items = perAsset
                .filter { !Self.roiChartExcludedStablecoins.contains($0.key.uppercased()) }
                .map { (asset: $0.key, value: $0.value.roi_pct) }
                .sorted { abs($0.value) > abs($1.value) }
            if items.isEmpty {
                emptyMessage("No ROI data")
            } else {
                BarChartSimpleView(items: items, valueLabel: "ROI %")
                    .frame(height: 300)
                    .padding()
            }
        } else {
            emptyMessage("No portfolio data")
        }
    }

    // MARK: - Chart 12: Largest wins and losses
    @ViewBuilder
    private var largestWinsLossesChart: some View {
        let items = Self.largestWinsAndLosses(trades: chartTrades, appState: appState, limit: 10)
        if items.isEmpty {
            emptyMessage("No trades with P&L")
        } else {
            LargestWinsLossesChartView(items: items)
                .frame(height: 400)
                .padding()
        }
    }

    // MARK: - Additional charts: by exchange, cash flow, profit factor, distribution, rolling Sharpe

    @ViewBuilder
    private var realizedPnlByExchangeChart: some View {
        let items = Self.realizedPnlByExchange(trades: chartTrades, appState: appState)
        if items.isEmpty {
            emptyMessage("No realized P&L by exchange")
        } else {
            BarChartSimpleView(items: items, valueLabel: "Realized P&L ($)")
                .frame(height: 260)
        }
    }

    @ViewBuilder
    private var feesByExchangeChart: some View {
        let items = Self.feesByExchange(trades: chartTrades)
        if items.isEmpty {
            emptyMessage("No fees by exchange")
        } else {
            BarChartSimpleView(items: items, valueLabel: "Fees ($)")
                .frame(height: 260)
        }
    }

    @ViewBuilder
    private var tradeVolumeByExchangeChart: some View {
        let items = Self.tradeVolumeByExchange(trades: chartTrades)
        if items.isEmpty {
            emptyMessage("No trades by exchange")
        } else {
            BarChartSimpleView(items: items, valueLabel: "Volume ($)")
                .frame(height: 260)
        }
    }

    @ViewBuilder
    private func depositsWithdrawalsChart(period: ChartPeriod) -> some View {
        let points = Self.depositsWithdrawalsByPeriod(trades: chartTrades, period: period)
        if points.isEmpty {
            emptyMessage("No deposits or withdrawals in period")
        } else {
            DepositsWithdrawalsChartView(points: points)
                .frame(height: 260)
        }
    }

    @ViewBuilder
    private var largestTradesBySizeChart: some View {
        let items = Self.largestTradesBySize(trades: chartTrades, limit: 10)
        if items.isEmpty {
            emptyMessage("No trades")
        } else {
            LargestWinsLossesChartView(items: items.map { ($0.label, $0.value) }, xAxisLabel: "Notional ($)")
                .frame(height: 320)
        }
    }

    @ViewBuilder
    private var profitFactorChart: some View {
        let (_, _, winTotal, lossTotal) = Self.winLossAggregates(trades: chartTrades, appState: appState)
        let factor = lossTotal > 0 ? winTotal / lossTotal : (winTotal > 0 ? 999.99 : 0)
        ProfitFactorCardView(factor: factor, winTotal: winTotal, lossTotal: lossTotal)
    }

    /// Profit factor section: KPI card plus bar chart (gross profit vs gross loss).
    @ViewBuilder
    private var profitFactorChartWithBars: some View {
        let (_, _, winTotal, lossTotal) = Self.winLossAggregates(trades: chartTrades, appState: appState)
        let factor = lossTotal > 0 ? winTotal / lossTotal : (winTotal > 0 ? 999.99 : 0)
        VStack(alignment: .leading, spacing: 12) {
            ProfitFactorCardView(factor: factor, winTotal: winTotal, lossTotal: lossTotal)
            if winTotal > 0 || lossTotal > 0 {
                BarChartSimpleView(
                    items: [
                        ("Gross profit", winTotal),
                        ("Gross loss", -lossTotal)
                    ],
                    valueLabel: "$"
                )
                .frame(height: 180)
            }
        }
    }

    @ViewBuilder
    private var tradeSizeDistributionChart: some View {
        let buckets = Self.tradeSizeDistribution(trades: chartTrades)
        if buckets.isEmpty {
            emptyMessage("No trade data")
        } else {
            HistogramChartView(buckets: buckets, valueLabel: "Number of trades")
                .frame(height: 260)
        }
    }

    @ViewBuilder
    private func tradeFrequencyChart(period: ChartPeriod) -> some View {
        let points = Self.tradeCountByPeriod(trades: chartTrades, period: period)
        if points.isEmpty {
            emptyMessage("No trades in period")
        } else {
            BarChartSimpleView(items: points.map { (asset: $0.date, value: Double($0.count)) }, valueLabel: "Trades")
                .frame(height: 260)
        }
    }

    @ViewBuilder
    private func netFlowChart(period: ChartPeriod) -> some View {
        let points = Self.netFlowByPeriod(trades: chartTrades, period: period)
        if points.isEmpty {
            emptyMessage("No trade flow in period")
        } else {
            NetFlowChartView(points: points)
                .frame(height: 260)
        }
    }

    @ViewBuilder
    private var realizedVsUnrealizedChart: some View {
        if let pm = appState.portfolioMetrics {
            RealizedVsUnrealizedChartView(realized: pm.realized_pnl, unrealized: pm.unrealized_pnl)
                .frame(height: 220)
        } else {
            emptyMessage("No portfolio data")
        }
    }

    @ViewBuilder
    private var holdTimeDistributionChart: some View {
        let days = MetricsService().holdTimesInDays(trades: chartTrades)
        let buckets = Self.bucketHoldTimes(days: days)
        if buckets.isEmpty {
            emptyMessage("No closed positions for hold time")
        } else {
            HistogramChartView(buckets: buckets, valueLabel: "Number of lots")
                .frame(height: 260)
        }
    }

    @ViewBuilder
    private func rollingSharpeChart(period: ChartPeriod) -> some View {
        let totalValue = appState.portfolioMetrics?.total_value ?? 0
        let points = MetricsService().rollingSharpeSeries(
            trades: chartTrades,
            costBasisMethod: appState.data.settings.cost_basis_method,
            currentTotalValue: totalValue,
            windowSize: 30
        )
        let filtered = filterPointsByPeriod(points, period: period)
        if filtered.isEmpty {
            emptyMessage("Not enough data for rolling Sharpe (need 30+ points)")
        } else {
            ChartView(points: filtered, yAxisLabel: "Sharpe ratio")
                .frame(height: 260)
        }
    }

    // MARK: - Helpers for volume, fees, win/loss, top/bottom trades

    private static func tradeVolumeByPeriod(
        trades: [Trade],
        period: ChartPeriod
    ) -> (buy: [(date: String, value: Double)], sell: [(date: String, value: Double)]) {
        let f = dateFormatter
        let endDate = trades.compactMap { f.date(from: $0.date) }.max() ?? Date()
        let startDate: Date
        switch period {
        case .d1: startDate = Calendar.current.date(byAdding: .day, value: -1, to: endDate) ?? endDate
        case .w1: startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate) ?? endDate
        case .m1: startDate = Calendar.current.date(byAdding: .month, value: -1, to: endDate) ?? endDate
        case .m3: startDate = Calendar.current.date(byAdding: .month, value: -3, to: endDate) ?? endDate
        case .m6: startDate = Calendar.current.date(byAdding: .month, value: -6, to: endDate) ?? endDate
        case .y1: startDate = Calendar.current.date(byAdding: .year, value: -1, to: endDate) ?? endDate
        case .all: startDate = Date.distantPast
        }
        var buyBuckets: [String: Double] = [:]
        var sellBuckets: [String: Double] = [:]
        for t in trades where f.date(from: t.date).map({ $0 >= startDate }) ?? false {
            let key: String
            if period == .d1 || period == .w1 {
                key = t.date
            } else {
                guard let d = f.date(from: t.date) else { continue }
                key = String(format: "%d-%02d", Calendar.current.component(.year, from: d), Calendar.current.component(.month, from: d))
            }
            if t.type == "BUY" {
                buyBuckets[key, default: 0] += t.total_value
            } else if t.type == "SELL" {
                sellBuckets[key, default: 0] += t.total_value
            }
        }
        let sortedKeys = (Set(buyBuckets.keys).union(Set(sellBuckets.keys))).sorted()
        let buyPoints = sortedKeys.map { (date: $0, value: buyBuckets[$0] ?? 0) }
        let sellPoints = sortedKeys.map { (date: $0, value: sellBuckets[$0] ?? 0) }
        return (buyPoints, sellPoints)
    }

    private static func feesSeries(trades: [Trade], period: ChartPeriod) -> [(date: String, value: Double)] {
        let sorted = trades.sorted { $0.date < $1.date }
        var cum: Double = 0
        var result: [(date: String, value: Double)] = []
        for t in sorted {
            cum += t.fee
            result.append((t.date, cum))
        }
        guard !result.isEmpty else { return [] }
        let f = dateFormatter
        let endDate = f.date(from: result[result.count - 1].date) ?? Date()
        let startDate: Date
        switch period {
        case .d1: startDate = Calendar.current.date(byAdding: .day, value: -1, to: endDate) ?? endDate
        case .w1: startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate) ?? endDate
        case .m1: startDate = Calendar.current.date(byAdding: .month, value: -1, to: endDate) ?? endDate
        case .m3: startDate = Calendar.current.date(byAdding: .month, value: -3, to: endDate) ?? endDate
        case .m6: startDate = Calendar.current.date(byAdding: .month, value: -6, to: endDate) ?? endDate
        case .y1: startDate = Calendar.current.date(byAdding: .year, value: -1, to: endDate) ?? endDate
        case .all: return result
        }
        return result.filter { guard let d = f.date(from: $0.date) else { return false }; return d >= startDate }
    }

    private static func winLossAggregates(
        trades: [Trade],
        appState: AppState
    ) -> (wins: Int, losses: Int, winTotal: Double, lossTotal: Double) {
        let metrics = MetricsService()
        let method = appState.data.settings.cost_basis_method
        var wins = 0, losses = 0
        var winTotal = 0.0, lossTotal = 0.0
        for t in trades {
            let pnl: Double?
            if t.type == "SELL" {
                pnl = metrics.realizedPnlForTrade(trades: trades, tradeId: t.id, costBasisMethod: method)
            } else if t.type == "BUY" {
                pnl = metrics.buyProfitPerTrade(trades: trades)[t.id]
            } else {
                pnl = nil
            }
            guard let p = pnl else { continue }
            if p > 0 { wins += 1; winTotal += p }
            else if p < 0 { losses += 1; lossTotal += abs(p) }
        }
        return (wins, losses, winTotal, lossTotal)
    }

    private static func largestWinsAndLosses(
        trades: [Trade],
        appState: AppState,
        limit: Int
    ) -> [(label: String, pnl: Double)] {
        let metrics = MetricsService()
        let method = appState.data.settings.cost_basis_method
        var list: [(tradeId: String, date: String, type: String, pnl: Double)] = []
        for t in trades {
            let pnl: Double?
            if t.type == "SELL" {
                pnl = metrics.realizedPnlForTrade(trades: trades, tradeId: t.id, costBasisMethod: method)
            } else if t.type == "BUY" {
                pnl = metrics.buyProfitPerTrade(trades: trades)[t.id]
            } else {
                pnl = nil
            }
            guard let p = pnl else { continue }
            list.append((t.id, t.date, t.type, p))
        }
        let sorted = list.sorted { abs($0.pnl) > abs($1.pnl) }
        return Array(sorted.prefix(limit)).map { item in
            let shortDate = String(item.date.prefix(10))
            let label = "\(item.type) \(shortDate) $\(String(format: "%.0f", item.pnl))"
            return (label: label, pnl: item.pnl)
        }
    }

    private static func realizedPnlByExchange(trades: [Trade], appState: AppState) -> [(asset: String, value: Double)] {
        let metrics = MetricsService()
        let method = appState.data.settings.cost_basis_method
        var sumByExchange: [String: Double] = [:]
        for t in trades where t.type == "SELL" {
            guard let pnl = metrics.realizedPnlForTrade(trades: trades, tradeId: t.id, costBasisMethod: method) else { continue }
            let ex = t.exchange.isEmpty ? "—" : t.exchange
            sumByExchange[ex, default: 0] += pnl
        }
        return sumByExchange.map { ($0.key, $0.value) }.sorted { abs($0.value) > abs($1.value) }
    }

    private static func feesByExchange(trades: [Trade]) -> [(asset: String, value: Double)] {
        var sum: [String: Double] = [:]
        for t in trades where t.fee > 0 {
            let ex = t.exchange.isEmpty ? "—" : t.exchange
            sum[ex, default: 0] += t.fee
        }
        return sum.map { ($0.key, $0.value) }.sorted { $0.value > $1.value }
    }

    private static func tradeVolumeByExchange(trades: [Trade]) -> [(asset: String, value: Double)] {
        var vol: [String: Double] = [:]
        for t in trades where t.type == "BUY" || t.type == "SELL" {
            let ex = t.exchange.isEmpty ? "—" : t.exchange
            vol[ex, default: 0] += t.total_value
        }
        return vol.map { ($0.key, $0.value) }.sorted { $0.value > $1.value }
    }

    private static func depositsWithdrawalsByPeriod(trades: [Trade], period: ChartPeriod) -> [(date: String, value: Double)] {
        let f = dateFormatter
        let cash = trades.filter { $0.asset == "USD" && ($0.type == "Deposit" || $0.type == "Withdrawal") }
        guard !cash.isEmpty else { return [] }
        let endDate = cash.compactMap { f.date(from: $0.date) }.max() ?? Date()
        let startDate: Date
        switch period {
        case .d1: startDate = Calendar.current.date(byAdding: .day, value: -1, to: endDate) ?? endDate
        case .w1: startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate) ?? endDate
        case .m1: startDate = Calendar.current.date(byAdding: .month, value: -1, to: endDate) ?? endDate
        case .m3: startDate = Calendar.current.date(byAdding: .month, value: -3, to: endDate) ?? endDate
        case .m6: startDate = Calendar.current.date(byAdding: .month, value: -6, to: endDate) ?? endDate
        case .y1: startDate = Calendar.current.date(byAdding: .year, value: -1, to: endDate) ?? endDate
        case .all: startDate = Date.distantPast
        }
        var bucket: [String: Double] = [:]
        for t in cash {
            guard let d = f.date(from: t.date), d >= startDate else { continue }
            let key = String(format: "%d-%02d", Calendar.current.component(.year, from: d), Calendar.current.component(.month, from: d))
            let amount = t.type == "Deposit" ? t.quantity : -t.quantity
            bucket[key, default: 0] += amount
        }
        return bucket.keys.sorted().map { (date: $0, value: bucket[$0] ?? 0) }
    }

    private static func largestTradesBySize(trades: [Trade], limit: Int) -> [(label: String, value: Double)] {
        let bySize = trades.filter { $0.type == "BUY" || $0.type == "SELL" }
            .sorted { $0.total_value > $1.total_value }
            .prefix(limit)
        return bySize.map { t in
            let shortDate = String(t.date.prefix(10))
            let label = "\(t.type) \(t.asset) \(shortDate) $\(String(format: "%.0f", t.total_value))"
            return (label: label, value: t.total_value)
        }
    }

    private static func tradeSizeDistribution(trades: [Trade]) -> [(bucket: String, count: Int)] {
        let values = trades.filter { $0.type == "BUY" || $0.type == "SELL" }.map(\.total_value)
        guard !values.isEmpty else { return [] }
        let boundaries: [(String, Double)] = [
            ("< $1k", 1_000),
            ("$1k–10k", 10_000),
            ("$10k–50k", 50_000),
            ("$50k–100k", 100_000),
            ("> $100k", Double.infinity)
        ]
        var counts = [0, 0, 0, 0, 0]
        for v in values {
            for (i, (_, up)) in boundaries.enumerated() {
                if v < up { counts[i] += 1; break }
            }
        }
        return zip(boundaries.map(\.0), counts).map { (bucket: $0.0, count: $0.1) }.filter { $0.count > 0 }
    }

    private static func tradeCountByPeriod(trades: [Trade], period: ChartPeriod) -> [(date: String, count: Int)] {
        let f = dateFormatter
        let endDate = trades.compactMap { f.date(from: $0.date) }.max() ?? Date()
        let startDate: Date
        switch period {
        case .d1: startDate = Calendar.current.date(byAdding: .day, value: -1, to: endDate) ?? endDate
        case .w1: startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate) ?? endDate
        case .m1: startDate = Calendar.current.date(byAdding: .month, value: -1, to: endDate) ?? endDate
        case .m3: startDate = Calendar.current.date(byAdding: .month, value: -3, to: endDate) ?? endDate
        case .m6: startDate = Calendar.current.date(byAdding: .month, value: -6, to: endDate) ?? endDate
        case .y1: startDate = Calendar.current.date(byAdding: .year, value: -1, to: endDate) ?? endDate
        case .all: startDate = Date.distantPast
        }
        var countByKey: [String: Int] = [:]
        for t in trades where f.date(from: t.date).map({ $0 >= startDate }) ?? false {
            let key: String
            if period == .d1 || period == .w1 {
                key = t.date
            } else if let d = f.date(from: t.date) {
                key = String(format: "%d-%02d", Calendar.current.component(.year, from: d), Calendar.current.component(.month, from: d))
            } else { continue }
            countByKey[key, default: 0] += 1
        }
        return countByKey.keys.sorted().map { (date: $0, count: countByKey[$0] ?? 0) }
    }

    private static func netFlowByPeriod(trades: [Trade], period: ChartPeriod) -> [(date: String, value: Double)] {
        let vol = tradeVolumeByPeriod(trades: trades, period: period)
        return zip(vol.buy.map(\.date), zip(vol.buy.map(\.value), vol.sell.map(\.value)))
            .map { (date: $0.0, value: $0.1.0 - $0.1.1) }
    }

    private static func bucketHoldTimes(days: [Double]) -> [(bucket: String, count: Int)] {
        guard !days.isEmpty else { return [] }
        let buckets: [(String, Double)] = [
            ("< 1 day", 1),
            ("1–7 days", 7),
            ("7–30 days", 30),
            ("30–90 days", 90),
            ("> 90 days", Double.infinity)
        ]
        var counts = [0, 0, 0, 0, 0]
        for d in days {
            for (i, (_, up)) in buckets.enumerated() {
                if d < up { counts[i] += 1; break }
            }
        }
        return zip(buckets.map(\.0), counts).map { (bucket: $0.0, count: $0.1) }.filter { $0.count > 0 }
    }
}

// Simple line chart using Swift Charts (macOS 13+)
struct ChartView: View {
    let points: [(date: String, value: Double)]
    var yAxisLabel: String = "Cumulative realized P&L ($)"

    private var chartData: [(Date, Double)] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return points.compactMap { (f.date(from: $0.date), $0.value) }.filter { $0.0 != nil }.map { ($0.0!, $0.1) }
    }

    var body: some View {
        if chartData.isEmpty {
            Text("No valid dates").foregroundColor(.secondary)
        } else {
            Chart(chartData, id: \.0) { item in
                LineMark(x: .value("Date", item.0), y: .value("P&L", item.1))
                    .interpolationMethod(.catmullRom)
                AreaMark(x: .value("Date", item.0), y: .value("P&L", item.1))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.linearGradient(colors: [.blue.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
            }
            .chartXAxisLabel("Date")
            .chartYAxisLabel(yAxisLabel)
        }
    }
}

// MARK: - Chart helper views (bar, pie, volume, win/loss, etc.)

/// Identifiable (asset, value) for Swift Charts pie/sector charts.
private struct AssetValueItem: Identifiable {
    let asset: String
    let value: Double
    var id: String { asset }
}

/// Bar chart for (label, value) pairs; supports positive/negative coloring.
struct BarChartSimpleView: View {
    let items: [(asset: String, value: Double)]
    var valueLabel: String = "Value"

    var body: some View {
        Chart(Array(items.enumerated()), id: \.offset) { _, item in
            BarMark(
                x: .value("Asset", item.asset),
                y: .value("Value", item.value)
            )
            .foregroundStyle(item.value >= 0 ? Color.green : Color.red)
        }
        .chartYAxisLabel(valueLabel)
    }
}

/// Grouped bar: buy volume vs sell volume by date.
struct TradeVolumeChartView: View {
    let buyPoints: [(date: String, value: Double)]
    let sellPoints: [(date: String, value: Double)]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private struct PeriodVolume: Identifiable {
        let id: String
        let date: Date
        let buy: Double
        let sell: Double
    }

    private var data: [PeriodVolume] {
        let keys = Set(buyPoints.map(\.date)).union(Set(sellPoints.map(\.date))).sorted()
        let buyMap = Dictionary(uniqueKeysWithValues: buyPoints.map { ($0.date, $0.value) })
        let sellMap = Dictionary(uniqueKeysWithValues: sellPoints.map { ($0.date, $0.value) })
        return keys.compactMap { key -> PeriodVolume? in
            guard let d = Self.dateFormatter.date(from: key) else { return nil }
            return PeriodVolume(
                id: key,
                date: d,
                buy: buyMap[key] ?? 0,
                sell: sellMap[key] ?? 0
            )
        }.sorted { $0.date < $1.date }
    }

    var body: some View {
        Chart(data) { item in
            BarMark(x: .value("Date", item.date), y: .value("Buy", item.buy))
                .foregroundStyle(.green)
            BarMark(x: .value("Date", item.date), y: .value("Sell", item.sell))
                .foregroundStyle(.red)
        }
        .chartLegend(position: .bottom)
        .chartYAxisLabel("Volume ($)")
    }
}

/// Win count and loss count (and optional $ totals) as bar or summary.
struct WinLossChartView: View {
    let wins: Int
    let losses: Int
    let winTotal: Double
    let lossTotal: Double

    private var data: [(label: String, count: Int, total: Double)] {
        [
            (label: "Winning trades", count: wins, total: winTotal),
            (label: "Losing trades", count: losses, total: lossTotal)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(Array(data.enumerated()), id: \.offset) { _, item in
                BarMark(
                    x: .value("Count", item.count),
                    y: .value("Type", item.label)
                )
                .foregroundStyle(item.label.hasPrefix("Win") ? Color.green : Color.red)
            }
            .chartXAxisLabel("Number of trades")
            Text("Wins total: $\(String(format: "%.2f", winTotal))  |  Losses total: $\(String(format: "%.2f", lossTotal))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// Grouped bar: cost basis vs current value per asset.
struct CostVsValueChartView: View {
    let items: [(asset: String, cost: Double, value: Double)]

    var body: some View {
        Chart(Array(items.enumerated()), id: \.offset) { _, item in
            BarMark(x: .value("Asset", item.asset), y: .value("Cost basis", item.cost))
                .foregroundStyle(.orange)
            BarMark(x: .value("Asset", item.asset), y: .value("Market value", item.value))
                .foregroundStyle(.blue)
        }
        .chartLegend(position: .bottom)
        .chartYAxisLabel("$")
    }
}

/// Horizontal bar chart for top/bottom trades by P&L or by size.
struct LargestWinsLossesChartView: View {
    let items: [(label: String, pnl: Double)]
    var xAxisLabel: String = "P&L ($)"

    var body: some View {
        Chart(Array(items.enumerated()), id: \.offset) { idx, item in
            BarMark(
                x: .value("Value", item.pnl),
                y: .value("Trade", String(item.label.prefix(30)))
            )
            .foregroundStyle(item.pnl >= 0 ? Color.green : Color.red)
        }
        .chartXAxisLabel(xAxisLabel)
    }
}

/// Profit factor (gross profit / gross loss) as a KPI card.
struct ProfitFactorCardView: View {
    let factor: Double
    let winTotal: Double
    let lossTotal: Double

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profit factor")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "%.2f", factor))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(factor >= 1 ? .green : .red)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Gross profit")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "$%.2f", winTotal))
                    .font(.subheadline)
                    .foregroundColor(.green)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Gross loss")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "$%.2f", lossTotal))
                    .font(.subheadline)
                    .foregroundColor(.red)
            }
        }
        .padding()
    }
}

/// Histogram: bucket label vs count.
struct HistogramChartView: View {
    let buckets: [(bucket: String, count: Int)]
    var valueLabel: String = "Count"

    var body: some View {
        Chart(Array(buckets.enumerated()), id: \.offset) { _, item in
            BarMark(
                x: .value("Bucket", item.bucket),
                y: .value(valueLabel, item.count)
            )
        }
        .chartYAxisLabel(valueLabel)
    }
}

/// Deposits (positive) and withdrawals (negative) by period; bar chart with green/red.
struct DepositsWithdrawalsChartView: View {
    let points: [(date: String, value: Double)]

    var body: some View {
        if points.isEmpty {
            Text("No data").foregroundColor(.secondary)
        } else {
            Chart(Array(points.enumerated()), id: \.offset) { _, item in
                BarMark(x: .value("Period", item.date), y: .value("Net", item.value))
                    .foregroundStyle(item.value >= 0 ? Color.green : Color.red)
            }
            .chartXAxisLabel("Period")
            .chartYAxisLabel("Net deposits ($)")
        }
    }
}

/// Net flow (buy − sell) by period; can be positive or negative.
struct NetFlowChartView: View {
    let points: [(date: String, value: Double)]

    var body: some View {
        if points.isEmpty {
            Text("No data").foregroundColor(.secondary)
        } else {
            Chart(Array(points.enumerated()), id: \.offset) { _, item in
                BarMark(x: .value("Period", item.date), y: .value("Net flow", item.value))
                    .foregroundStyle(item.value >= 0 ? Color.green : Color.red)
            }
            .chartXAxisLabel("Period")
            .chartYAxisLabel("Net flow ($)")
        }
    }
}

/// Current realized vs unrealized P&L as two bars.
struct RealizedVsUnrealizedChartView: View {
    let realized: Double
    let unrealized: Double

    private var data: [(label: String, value: Double)] {
        [("Realized", realized), ("Unrealized", unrealized)]
    }

    var body: some View {
        Chart(Array(data.enumerated()), id: \.offset) { _, item in
            BarMark(
                x: .value("Type", item.label),
                y: .value("P&L ($)", item.value)
            )
            .foregroundStyle(item.value >= 0 ? Color.green : Color.red)
        }
        .chartYAxisLabel("P&L ($)")
    }
}

// MARK: - Trading tab

struct TradingTabView: View {
    @EnvironmentObject var appState: AppState
    var showSettings: () -> Void

    private let tradingExchanges = ["Kraken", "Bitstamp", "Binance", "Binance Testnet"]
    private let orderTypes: [OrderType] = [.market, .limit, .stopLoss, .stopLossLimit, .takeProfit, .takeProfitLimit, .iceberg, .trailingStop, .trailingStopLimit]
    private let timeInForceOptions: [(TimeInForce, String)] = [
        (.gtc, "GTC – Good-Til-Cancelled: order stays until filled or cancelled."),
        (.fok, "FOK – Fill-Or-Kill: execute entire quantity immediately or cancel."),
        (.ioc, "IOC – Immediate-Or-Cancel: fill as much as possible immediately, cancel the rest."),
        (.gtd, "GTD – Good-Til-Date: order valid until chosen expiry date/time."),
        (.daily, "Daily – valid for the trading day only."),
    ]

    @State private var selectedExchange = "Kraken"
    @State private var buySell: OrderSide = .buy
    @State private var orderType: OrderType = .limit
    @State private var symbol = "BTC/USD"
    @State private var priceStr = ""
    @State private var amountStr = ""
    @State private var postOnly = false
    @State private var timeInForce: TimeInForce = .gtc
    @State private var gtdExpire = Date().addingTimeInterval(86400)
    @State private var oso = false
    @State private var isPlacing = false
    @State private var placeError: String?

    private var availableBalanceAsset: Double {
        guard let bal = appState.tradingBalances?.availableByAsset else { return 0 }
        let base = symbol.split(separator: "/").first.map(String.init) ?? "BTC"
        return bal[base] ?? bal[base.uppercased()] ?? 0
    }

    private var availableBalanceUSD: Double {
        guard let bal = appState.tradingBalances?.availableByAsset else { return 0 }
        return bal["USD"] ?? 0
    }

    private var totalBalanceAsset: Double {
        guard let bal = appState.tradingBalances?.totalByAsset else { return 0 }
        let base = symbol.split(separator: "/").first.map(String.init) ?? "BTC"
        return bal[base] ?? bal[base.uppercased()] ?? 0
    }

    private var totalBalanceUSD: Double {
        guard let bal = appState.tradingBalances?.totalByAsset else { return 0 }
        return bal["USD"] ?? 0
    }

    private var estimatedFee: Double {
        guard let tier = appState.tradingFeeTier else { return 0 }
        let amount = Double(amountStr) ?? 0
        let p = Double(priceStr) ?? 0
        let value = amount * (orderType == .market ? 0 : (p > 0 ? p : 1))
        let rate = orderType == .market ? tier.takerPercent : tier.makerPercent
        return value * (rate / 100)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Picker("Exchange", selection: $selectedExchange) {
                        ForEach(tradingExchanges, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    .onChange(of: selectedExchange) { _ in
                        Task { await appState.refreshTradingData(exchange: selectedExchange) }
                    }
                    if !appState.isExchangeAPIConfigured(selectedExchange) {
                        Text("Not configured").font(.caption).foregroundColor(.orange)
                        Button("Settings") { showSettings() }.buttonStyle(.borderless)
                    } else {
                        Button("Refresh") { Task { await appState.refreshTradingData(exchange: selectedExchange) } }.buttonStyle(.borderless)
                    }
                }

                if let err = appState.tradingLoadError {
                    Text(err).font(.caption).foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker("", selection: $buySell) {
                    Text("Buy").tag(OrderSide.buy)
                    Text("Sell").tag(OrderSide.sell)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                Picker("Order type", selection: $orderType) {
                    ForEach(orderTypes, id: \.self) { type in
                        Text(orderTypeLabel(type)).tag(type)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Picker("Pair", selection: $symbol) {
                        Text("BTC/USD").tag("BTC/USD")
                        Text("ETH/USD").tag("ETH/USD")
                    }
                    if orderType != .market {
                        TextField("Price", text: $priceStr).textFieldStyle(.roundedBorder).frame(width: 120)
                    }
                    TextField("Amount", text: $amountStr).textFieldStyle(.roundedBorder).frame(width: 120)
                }

                HStack(spacing: 8) {
                    Text("Quick add:").font(.caption)
                    ForEach([25, 50, 75, 100], id: \.self) { pct in
                        Button("\(pct)%") {
                            let avail = buySell == .buy ? availableBalanceUSD : availableBalanceAsset
                            if buySell == .buy, let price = Double(priceStr), price > 0 {
                                amountStr = String(format: "%.8f", (avail * Double(pct) / 100) / price)
                            } else {
                                amountStr = String(format: "%.8f", avail * Double(pct) / 100)
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Toggle("Post only", isOn: $postOnly).toggleStyle(.checkbox)
                Picker("Time in force", selection: $timeInForce) {
                    ForEach(timeInForceOptions, id: \.0) { tif, desc in
                        Text(String(describing: tif.rawValue)).tag(tif)
                    }
                }
                .pickerStyle(.menu)
                if timeInForce == .gtd || timeInForce == .daily {
                    DatePicker("Expires", selection: $gtdExpire, displayedComponents: [.date, .hourAndMinute])
                }
                ForEach(timeInForceOptions, id: \.0) { tif, desc in
                    if timeInForce == tif {
                        Text(desc).font(.caption).foregroundColor(.secondary)
                    }
                }
                Toggle("OSO (One-Cancels-Other)", isOn: $oso).toggleStyle(.checkbox)

                Divider()
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total balance").font(.headline)
                        Text("\(symbol): \(String(format: "%.8f", totalBalanceAsset))").font(.caption)
                        Text("USD: \(String(format: "%.2f", totalBalanceUSD))").font(.caption)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Available balance").font(.headline)
                        Text("\(symbol): \(String(format: "%.8f", availableBalanceAsset))").font(.caption)
                        Text("USD: \(String(format: "%.2f", availableBalanceUSD))").font(.caption)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fee / Volume").font(.headline)
                        if let tier = appState.tradingFeeTier {
                            Text("Maker \(String(format: "%.2f", tier.makerPercent))%  Taker \(String(format: "%.2f", tier.takerPercent))%").font(.caption)
                        }
                        if let vol = appState.tradingVolume30d, vol > 0 {
                            Text("30d volume: $\(String(format: "%.0f", vol))").font(.caption)
                        }
                        Text("Est. fee: $\(String(format: "%.2f", estimatedFee))").font(.caption)
                    }
                }

                if let msg = appState.tradingOrderMessage {
                    Text(msg).font(.caption).foregroundColor(.green)
                }
                if let err = placeError {
                    Text(err).font(.caption).foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(buySell == .buy ? "Place buy order" : "Place sell order") {
                    placeOrder()
                }
                .disabled(isPlacing || !appState.isExchangeAPIConfigured(selectedExchange))
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .onAppear {
            Task { await appState.refreshTradingData(exchange: selectedExchange) }
        }
    }

    private func orderTypeLabel(_ t: OrderType) -> String {
        switch t {
        case .market: return "Market"
        case .limit: return "Limit"
        case .stopLoss: return "Stop loss"
        case .stopLossLimit: return "Stop loss limit"
        case .takeProfit: return "Take profit"
        case .takeProfitLimit: return "Take profit limit"
        case .iceberg: return "Iceberg"
        case .trailingStop: return "Trailing stop"
        case .trailingStopLimit: return "Trailing stop limit"
        }
    }

    private func placeOrder() {
        placeError = nil
        appState.tradingOrderMessage = nil
        let amount = Double(amountStr) ?? 0
        guard amount > 0 else { placeError = "Enter amount"; return }
        let price = orderType == .market ? nil : Double(priceStr)
        if orderType != .market, price == nil || price! <= 0 {
            placeError = "Enter price for this order type"
            return
        }
        if buySell == .sell, amount > availableBalanceAsset {
            placeError = "Insufficient balance (available: \(String(format: "%.8f", availableBalanceAsset)))"
            return
        }
        if buySell == .buy, let p = price, p > 0, amount * p > availableBalanceUSD {
            placeError = "Insufficient USD (available: \(String(format: "%.2f", availableBalanceUSD)))"
            return
        }
        isPlacing = true
        let params = OrderParams(
            side: buySell,
            orderType: orderType,
            symbol: symbol,
            amount: amount,
            price: price,
            postOnly: postOnly,
            timeInForce: timeInForce,
            expireTime: (timeInForce == .gtd || timeInForce == .daily) ? gtdExpire : nil,
            oso: oso
        )
        Task {
            do {
                let result = try await appState.placeTradingOrder(exchange: selectedExchange, params: params)
                appState.tradingOrderMessage = "Order placed: \(result.orderId)"
                amountStr = ""
                Task { await appState.refreshTradingData(exchange: selectedExchange) }
            } catch {
                placeError = error.localizedDescription
            }
            isPlacing = false
        }
    }
}

// MARK: - Form-friendly text field style (macOS)

/// Applies a visible background and border so text fields render correctly inside Form in dark mode
/// (avoids the flat grey block appearance of .roundedBorder in grouped forms).
private struct FormInputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
            )
    }
}

private extension View {
    func formInputStyle() -> some View {
        modifier(FormInputStyle())
    }
}

// MARK: - Trading API keys (Settings)

struct TradingAPIKeysSection: View {
    @EnvironmentObject var appState: AppState
    @State private var krakenKey = ""
    @State private var krakenSecret = ""
    @State private var bitstampKey = ""
    @State private var bitstampSecret = ""
    @State private var binanceKey = ""
    @State private var binanceSecret = ""
    @State private var binanceTestnetKey = ""
    @State private var binanceTestnetSecret = ""

    var body: some View {
        Group {
            TradingAPIKeyRow(
                exchange: "Kraken",
                isConfigured: appState.isExchangeAPIConfigured("Kraken"),
                apiKey: $krakenKey,
                secret: $krakenSecret,
                onSave: {
                    if !krakenKey.isEmpty, !krakenSecret.isEmpty {
                        _ = appState.saveExchangeAPICredentials(exchange: "Kraken", apiKey: krakenKey.trimmingCharacters(in: .whitespaces), secret: krakenSecret)
                        krakenKey = ""
                        krakenSecret = ""
                    }
                },
                onRemove: {
                    appState.removeExchangeAPICredentials(exchange: "Kraken")
                    krakenKey = ""
                    krakenSecret = ""
                }
            )
            TradingAPIKeyRow(
                exchange: "Bitstamp",
                isConfigured: appState.isExchangeAPIConfigured("Bitstamp"),
                apiKey: $bitstampKey,
                secret: $bitstampSecret,
                onSave: {
                    if !bitstampKey.isEmpty, !bitstampSecret.isEmpty {
                        _ = appState.saveExchangeAPICredentials(exchange: "Bitstamp", apiKey: bitstampKey.trimmingCharacters(in: .whitespaces), secret: bitstampSecret)
                        bitstampKey = ""
                        bitstampSecret = ""
                    }
                },
                onRemove: {
                    appState.removeExchangeAPICredentials(exchange: "Bitstamp")
                    bitstampKey = ""
                    bitstampSecret = ""
                }
            )
            TradingAPIKeyRow(
                exchange: "Binance",
                isConfigured: appState.isExchangeAPIConfigured("Binance"),
                apiKey: $binanceKey,
                secret: $binanceSecret,
                onSave: {
                    if !binanceKey.isEmpty, !binanceSecret.isEmpty {
                        _ = appState.saveExchangeAPICredentials(exchange: "Binance", apiKey: binanceKey.trimmingCharacters(in: .whitespaces), secret: binanceSecret)
                        binanceKey = ""
                        binanceSecret = ""
                    }
                },
                onRemove: {
                    appState.removeExchangeAPICredentials(exchange: "Binance")
                    binanceKey = ""
                    binanceSecret = ""
                }
            )
            TradingAPIKeyRow(
                exchange: "Binance Testnet",
                isConfigured: appState.isExchangeAPIConfigured("Binance Testnet"),
                apiKey: $binanceTestnetKey,
                secret: $binanceTestnetSecret,
                onSave: {
                    if !binanceTestnetKey.isEmpty, !binanceTestnetSecret.isEmpty {
                        _ = appState.saveExchangeAPICredentials(exchange: "Binance Testnet", apiKey: binanceTestnetKey.trimmingCharacters(in: .whitespaces), secret: binanceTestnetSecret)
                        binanceTestnetKey = ""
                        binanceTestnetSecret = ""
                    }
                },
                onRemove: {
                    appState.removeExchangeAPICredentials(exchange: "Binance Testnet")
                    binanceTestnetKey = ""
                    binanceTestnetSecret = ""
                }
            )
        }
    }
}

struct TradingAPIKeyRow: View {
    let exchange: String
    let isConfigured: Bool
    @Binding var apiKey: String
    @Binding var secret: String
    let onSave: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(exchange).fontWeight(.medium)
                if isConfigured {
                    Text("Configured").font(.caption).foregroundColor(.green)
                } else {
                    Text("Not configured").font(.caption).foregroundColor(.secondary)
                }
            }
            if isConfigured {
                HStack {
                    Text("API key and secret saved.").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Remove", role: .destructive) { onRemove() }.buttonStyle(.borderless)
                }
            } else {
                TextField("API Key", text: $apiKey).formInputStyle()
                SecureField("Secret", text: $secret).formInputStyle()
                Button("Save") { onSave() }.buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings view

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @AppStorage("tabOrder") private var tabOrderRaw = defaultTabOrderKey
    @State private var tabOrder: [String] = []
    @State private var defaultExchange: String = "Bitstamp"
    @State private var costBasisMethod: String = "average"
    @State private var isClient: Bool = false
    @State private var clientPct: Double = 0
    @State private var apiEnabled: Bool = false
    @State private var apiPortStr: String = "38472"
    @State private var webhookURLStr: String = ""
    @State private var showResetConfirm = false
    @State private var showRestoreConfirm = false
    @State private var pendingRestoreData: Data? = nil
    @State private var restoreBackupExportedAt: String? = nil
    @State private var showExchangeSheet = false
    @State private var showAlertRuleSheet = false
    @State private var exchangeSheetName = ""
    @State private var exchangeSheetMaker = "0.1"
    @State private var exchangeSheetTaker = "0.1"
    @State private var exchangeSheetEditing: String? = nil
    @AppStorage("FuckYouMoney.polymarketGammaBaseURL") private var polymarketGammaBaseURL = ""
    @AppStorage("FuckYouMoney.polymarketClobBaseURL") private var polymarketClobBaseURL = ""

    private var parsedTabOrder: [String] {
        let parsed = tabOrderRaw.split(separator: ",").map(String.init)
        let valid = parsed.filter { tabIds.contains($0) }
        let missing = tabIds.filter { !valid.contains($0) }
        return valid + missing
    }

    private func tabLabelForId(_ id: String) -> String {
        switch id {
        case "dashboard": return "Dashboard"
        case "trading": return "Trading"
        case "transactions": return "Transactions"
        case "charts": return "Charts"
        case "assets": return "Assets"
        case "assistant": return "Assistant"
        case "polymarket": return "Polymarket"
        default: return id
        }
    }

    var body: some View {
        Form {
            Section("Getting started") {
                Text("Connect an exchange (Trading API keys), import trades (File → Import), or add trades in the Transactions tab. Enable Local API for bots; use \"Open API docs in browser\" when the API is on.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("Tab order") {
                Text("Use Move Up / Move Down to reorder. Default: Dashboard, Trading, Transactions, Charts, Assets, Assistant.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(Array(tabOrder.enumerated()), id: \.element) { index, id in
                    HStack {
                        Text(tabLabelForId(id))
                        Spacer()
                        HStack(spacing: 4) {
                            Button {
                                if index > 0 {
                                    tabOrder.move(fromOffsets: [index], toOffset: index - 1)
                                    tabOrderRaw = tabOrder.joined(separator: ",")
                                }
                            } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            Button {
                                if index < tabOrder.count - 1 {
                                    tabOrder.move(fromOffsets: [index], toOffset: index + 2)
                                    tabOrderRaw = tabOrder.joined(separator: ",")
                                }
                            } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless)
                            .disabled(index == tabOrder.count - 1)
                        }
                    }
                }
            }
            Picker("Default exchange", selection: $defaultExchange) {
                ForEach(Array(appState.data.settings.fee_structure.keys.sorted()), id: \.self) { Text($0).tag($0) }
            }
            Picker("Cost basis method", selection: $costBasisMethod) {
                Text("FIFO").tag("fifo")
                Text("LIFO").tag("lifo")
                Text("Average").tag("average")
            }
            Toggle("Client mode", isOn: $isClient)
            if isClient {
                TextField("Client %", value: $clientPct, format: .number)
                    .frame(width: 80)
                    .formInputStyle()
            }
            Section("Exchange fees") {
                ForEach(Array(appState.data.settings.fee_structure.keys.sorted()), id: \.self) { name in
                    if let fees = appState.data.settings.fee_structure[name] {
                        HStack {
                            Text(name).fontWeight(.medium)
                            Text(String(format: "Maker %.2f%%", fees.maker)).font(.caption).foregroundColor(.secondary)
                            Text(String(format: "Taker %.2f%%", fees.taker)).font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Button("Edit") {
                                exchangeSheetEditing = name
                                exchangeSheetName = name
                                exchangeSheetMaker = String(format: "%.2f", fees.maker)
                                exchangeSheetTaker = String(format: "%.2f", fees.taker)
                                showExchangeSheet = true
                            }
                            .buttonStyle(.bordered)
                            Button("Remove", role: .destructive) {
                                appState.removeExchange(name: name)
                                if defaultExchange == name { defaultExchange = appState.data.settings.fee_structure.keys.sorted().first ?? "Wallet" }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                Button("Add exchange…") {
                    exchangeSheetEditing = nil
                    exchangeSheetName = ""
                    exchangeSheetMaker = "0.1"
                    exchangeSheetTaker = "0.1"
                    showExchangeSheet = true
                }
            }
            Section("Trading API keys") {
                TradingAPIKeysSection()
            }
            Section("Local API") {
                Toggle("Enable local API", isOn: $apiEnabled)
                if apiEnabled {
                    TextField("Port", text: $apiPortStr)
                        .frame(width: 80)
                        .formInputStyle()
                    HStack {
                        Button("Open API docs in browser") {
                            let port = appState.apiPort > 0 ? appState.apiPort : 38472
                            if let url = URL(string: "http://127.0.0.1:\(port)/v1/docs") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    TextField("Webhook URL (optional)", text: $webhookURLStr)
                        .textFieldStyle(.roundedBorder)
                    Text("POSTed when trades are added or portfolio is refreshed (e.g. for Crank or Slack).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Section("Polymarket") {
                Text("Optional overrides for API base URLs. Leave blank to use defaults (Gamma: gamma-api.polymarket.com, CLOB: clob.polymarket.com).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Gamma API base (optional)", text: $polymarketGammaBaseURL)
                    .textFieldStyle(.roundedBorder)
                TextField("CLOB API base (optional)", text: $polymarketClobBaseURL)
                    .textFieldStyle(.roundedBorder)
            }
            Section("Alerts") {
                Toggle("Enable alerts", isOn: Binding(
                    get: { appState.alertsEnabled },
                    set: {
                        appState.alertsEnabled = $0
                        if $0 { requestNotificationPermission() }
                    }
                ))
                if appState.alertsEnabled {
                    ForEach(appState.alertRules) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.type).font(.caption).fontWeight(.medium)
                                Text("value: \(rule.value)\(rule.asset.map { ", asset: \($0)" } ?? "")").font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { rule.enabled },
                                set: { _ in
                                    var r = rule
                                    r.enabled.toggle()
                                    appState.updateAlertRule(r)
                                }
                            )).labelsHidden()
                            Button("Delete", role: .destructive) { appState.removeAlertRule(id: rule.id) }.buttonStyle(.borderless)
                        }
                    }
                    Button("Add alert rule…") { showAlertRuleSheet = true }.buttonStyle(.bordered)
                }
                Text("Alerts evaluate on refresh. Triggered alerts show in Dashboard and can POST to your webhook and send macOS notifications.")
                Toggle("Notify when new noteworthy news appears", isOn: Binding(
                    get: { appState.newsNotificationsEnabled },
                    set: {
                        appState.newsNotificationsEnabled = $0
                        if $0 { requestNotificationPermission() }
                    }
                ))
                Text("When enabled, a macOS notification is sent for new headlines (Fed, rates, SEC, crypto, etc.) each time Dashboard news is loaded or refreshed. Up to 3 new items per refresh.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("Data") {
                Text(appState.customDataDirectoryPath ?? "Default (Application Support)")
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack {
                    Button("Use existing folder…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            appState.setDataDirectory(url: url)
                        }
                    }
                    Button("Use default") {
                        appState.setDataDirectory(url: nil)
                    }
                }
                Button("Backup all data…") {
                    guard let data = appState.backupData() else { return }
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.json]
                    panel.nameFieldStringValue = appState.backupDefaultFilename()
                    if panel.runModal() == .OK, let url = panel.url {
                        try? data.write(to: url)
                        appState.appendActivity("Backed up all data to \(url.lastPathComponent)")
                    }
                }
                Button("Restore from backup…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.json]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
                        pendingRestoreData = data
                        restoreBackupExportedAt = appState.backupExportedAt(data: data)
                        showRestoreConfirm = true
                    }
                }
                Button("Reset all data…", role: .destructive) {
                    showResetConfirm = true
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.visible)
        .scrollIndicators(.visible)
        .onAppear {
            tabOrder = parsedTabOrder
            defaultExchange = appState.data.settings.default_exchange
            costBasisMethod = appState.data.settings.cost_basis_method
            isClient = appState.data.settings.is_client
            clientPct = Double(appState.data.settings.client_percentage)
            apiEnabled = appState.apiEnabled
            apiPortStr = appState.apiPort > 0 ? String(appState.apiPort) : "38472"
            webhookURLStr = appState.webhookURL ?? ""
        }
        .frame(minWidth: 480, idealWidth: 480, minHeight: 420, idealHeight: 620, maxHeight: 720)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Settings").font(.headline)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    apply()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .keyboardShortcut(.cancelAction)
            }
        }
        .alert("Reset all data?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) { showResetConfirm = false }
            Button("Reset", role: .destructive) {
                appState.resetAllData()
                showResetConfirm = false
                dismiss()
            }
        } message: {
            Text("This will clear all trades and reset accounts and settings to defaults. This cannot be undone.")
        }
        .alert("Restore from backup?", isPresented: $showRestoreConfirm) {
            Button("Cancel", role: .cancel) {
                pendingRestoreData = nil
                restoreBackupExportedAt = nil
                showRestoreConfirm = false
            }
            Button("Restore") {
                if let data = pendingRestoreData {
                    if let err = appState.restoreFromBackup(data: data) {
                        appState.errorMessage = err
                    } else {
                        appState.appendActivity("Restored from backup")
                        dismiss()
                    }
                }
                pendingRestoreData = nil
                restoreBackupExportedAt = nil
                showRestoreConfirm = false
            }
        } message: {
            Text(restoreBackupExportedAt.map { "Backup from \($0). This will replace all users, trades, settings, and price history. Continue?" } ?? "This will replace all users, trades, settings, and price history with the backup. Continue?")
        }
        .sheet(isPresented: $showExchangeSheet) {
            exchangeFeeSheet
        }
        .sheet(isPresented: $showAlertRuleSheet) {
            AddAlertRuleSheet(appState: appState, onDismiss: { showAlertRuleSheet = false })
        }
    }

    private var exchangeFeeSheet: some View {
        VStack(spacing: 16) {
            Text(exchangeSheetEditing != nil ? "Edit exchange" : "Add exchange").font(.headline)
            TextField("Exchange name", text: $exchangeSheetName).textFieldStyle(.roundedBorder).frame(width: 200)
                .disabled(exchangeSheetEditing != nil)
            TextField("Maker %", text: $exchangeSheetMaker).textFieldStyle(.roundedBorder).frame(width: 80)
            TextField("Taker %", text: $exchangeSheetTaker).textFieldStyle(.roundedBorder).frame(width: 80)
            HStack {
                Button("Cancel") { showExchangeSheet = false }
                Button("Save") {
                    let maker = Double(exchangeSheetMaker) ?? 0.1
                    let taker = Double(exchangeSheetTaker) ?? 0.1
                    if let existing = exchangeSheetEditing {
                        appState.updateExchange(name: existing, maker: maker, taker: taker)
                    } else if !exchangeSheetName.isEmpty {
                        appState.addExchange(name: exchangeSheetName.trimmingCharacters(in: .whitespaces), maker: maker, taker: taker)
                    }
                    showExchangeSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 280)
    }

    private func apply() {
        appState.data.settings.default_exchange = defaultExchange
        appState.data.settings.cost_basis_method = costBasisMethod
        appState.data.settings.is_client = isClient
        appState.data.settings.client_percentage = clientPct
        appState.save()
        appState.recomputeMetrics()
        appState.apiEnabled = apiEnabled
        appState.apiPort = Int(apiPortStr) ?? 38472
        appState.webhookURL = webhookURLStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : webhookURLStr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

// MARK: - Add Alert Rule sheet

struct AddAlertRuleSheet: View {
    @ObservedObject var appState: AppState
    var onDismiss: () -> Void
    @State private var ruleType = "portfolio_value_below"
    @State private var valueStr = "10000"
    @State private var assetStr = ""

    private static let alertTypes = [
        ("portfolio_value_below", "Portfolio value below"),
        ("portfolio_value_above", "Portfolio value above"),
        ("asset_pct_down_24h", "Asset % down in 24h"),
        ("drawdown_above_pct", "Drawdown above %"),
        ("asset_pct_of_portfolio_above", "Asset % of portfolio above"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Add alert rule").font(.headline)
            Picker("Type", selection: $ruleType) {
                ForEach(Self.alertTypes, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.menu)
            TextField("Value (number)", text: $valueStr).textFieldStyle(.roundedBorder)
            TextField("Asset (optional, for asset_* rules)", text: $assetStr).textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { onDismiss() }
                Button("Save") {
                    let value = Double(valueStr) ?? 0
                    let rule = AlertRule(
                        id: UUID().uuidString,
                        type: ruleType,
                        value: value,
                        asset: assetStr.trimmingCharacters(in: .whitespaces).isEmpty ? nil : assetStr.trimmingCharacters(in: .whitespaces),
                        enabled: true
                    )
                    appState.addAlertRule(rule)
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

// MARK: - Dialog sheets (Add user, Switch user, Manage users, New account, Manage accounts, About, Export, Import)

struct AddUserSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    let onDismiss: () -> Void
    @State private var username = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add User").font(.headline)
            TextField("Username", text: $username).textFieldStyle(.roundedBorder).frame(width: 200)
            HStack {
                Button("Cancel") { dismiss(); onDismiss() }
                Button("Add") {
                    let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty, appState.storage.addUser(name) {
                        appState.users = appState.storage.loadUsers()
                        appState.currentUser = name
                        appState.data = (try? appState.storage.loadData(username: name)) ?? appState.data
                        appState.recomputeMetrics()
                        dismiss(); onDismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 300)
    }
}

struct SwitchUserSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Switch User").font(.headline)
            List(appState.users, id: \.self) { user in
                Button(user) {
                    appState.currentUser = user
                    appState.load()
                    dismiss(); onDismiss()
                }
            }
            Button("Cancel") { dismiss(); onDismiss() }
        }
        .padding()
        .frame(width: 250, height: 300)
    }
}

struct ManageUsersSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Manage Users").font(.headline)
            List(appState.users, id: \.self) { user in
                HStack {
                    Text(user)
                    Spacer()
                    if appState.users.count > 1 {
                        Button("Delete", role: .destructive) {
                            if appState.storage.deleteUser(user) {
                                appState.users = appState.storage.loadUsers()
                                if appState.currentUser == user { appState.currentUser = appState.users.first ?? "Default"; appState.load() }
                                dismiss(); onDismiss()
                            }
                        }
                    }
                }
            }
            Button("Done") { dismiss(); onDismiss() }
        }
        .padding()
        .frame(width: 320, height: 280)
    }
}

struct NewAccountSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    let onDismiss: () -> Void
    @State private var name = ""
    @State private var selectedGroupId: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("New Account").font(.headline)
            TextField("Account name", text: $name).textFieldStyle(.roundedBorder).frame(width: 220)
            Picker("Group", selection: $selectedGroupId) {
                ForEach(appState.data.account_groups, id: \.id) { Text($0.name).tag($0.id) }
            }
            .onAppear { selectedGroupId = appState.data.account_groups.first?.id ?? "" }
            HStack {
                Button("Cancel") { dismiss(); onDismiss() }
                Button("Create") {
                    let groupId = selectedGroupId.isEmpty ? (appState.data.account_groups.first?.id ?? "") : selectedGroupId
                    if !groupId.isEmpty {
                        appState.addAccount(name: name.isEmpty ? "New" : name, groupId: groupId)
                    }
                    dismiss(); onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

struct AddGroupSheet: View {
    @EnvironmentObject var appState: AppState
    let onDismiss: () -> Void
    let onAdd: (String) -> Void
    @State private var name = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Portfolio").font(.headline)
            TextField("Portfolio name", text: $name).textFieldStyle(.roundedBorder).frame(width: 220)
            HStack {
                Button("Cancel") { onDismiss() }
                Button("Add") {
                    onAdd(name.isEmpty ? "New Portfolio" : name)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 300)
    }
}

struct EditGroupSheet: View {
    let group: AccountGroup
    let onDismiss: () -> Void
    let onSave: (String) -> Void
    @State private var name = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Portfolio").font(.headline)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).frame(width: 220)
            HStack {
                Button("Cancel") { onDismiss() }
                Button("Save") { onSave(name.isEmpty ? group.name : name) }.buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 300)
        .onAppear { name = group.name }
    }
}

struct EditAccountSheet: View {
    @EnvironmentObject var appState: AppState
    let account: Account
    let onDismiss: () -> Void
    let onSave: (String, String) -> Void
    @State private var name = ""
    @State private var selectedGroupId: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Account").font(.headline)
            TextField("Account name", text: $name).textFieldStyle(.roundedBorder).frame(width: 220)
            Picker("Group", selection: $selectedGroupId) {
                Text("(No group)").tag("")
                ForEach(appState.data.account_groups) { g in
                    Text(g.name).tag(g.id)
                }
            }
            HStack {
                Button("Cancel") { onDismiss() }
                Button("Save") {
                    onSave(name.isEmpty ? account.name : name, selectedGroupId)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 320)
        .onAppear {
            name = account.name
            selectedGroupId = account.account_group_id ?? (appState.data.account_groups.first?.id ?? "")
        }
    }
}

struct EditProjectionSheet: View {
    let row: [String]
    let onDismiss: () -> Void
    let onSave: ([String]) -> Void
    @State private var asset: String = ""
    @State private var type: String = ""
    @State private var price: String = ""
    @State private var qty: String = ""
    @State private var amount: String = ""
    @State private var account: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit projection row").font(.headline)
            TextField("Asset", text: $asset).textFieldStyle(.roundedBorder)
            TextField("Type", text: $type).textFieldStyle(.roundedBorder)
            TextField("Price ($)", text: $price).textFieldStyle(.roundedBorder)
            TextField("Qty", text: $qty).textFieldStyle(.roundedBorder)
            TextField("Amount ($)", text: $amount).textFieldStyle(.roundedBorder)
            TextField("Account", text: $account).textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { onDismiss() }
                Button("Save") {
                    onSave([asset, type, price, qty, amount, account])
                }.buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 320)
        .onAppear {
            asset = row.count > 0 ? row[0] : ""
            type = row.count > 1 ? row[1] : ""
            price = row.count > 2 ? row[2] : ""
            qty = row.count > 3 ? row[3] : ""
            amount = row.count > 4 ? row[4] : ""
            account = row.count > 5 ? row[5] : ""
        }
    }
}

struct ManageAccountsSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    let onDismiss: () -> Void
    @State private var accountToEdit: Account?

    var body: some View {
        VStack(spacing: 16) {
            Text("Manage Accounts").font(.headline)
            List {
                ForEach(appState.data.account_groups) { group in
                    Section(group.name) {
                        ForEach(accountsIn(group)) { acc in
                            Text(acc.name)
                                .contextMenu {
                                    Button("Edit account…") { accountToEdit = acc }
                                    Button("Delete", role: .destructive) { appState.deleteAccount(id: acc.id) }
                                }
                        }
                    }
                }
            }
            Button("Done") { dismiss(); onDismiss() }
        }
        .padding()
        .frame(width: 300, height: 320)
        .sheet(item: $accountToEdit) { acc in
            EditAccountSheet(account: acc, onDismiss: { accountToEdit = nil }, onSave: { name, gid in
                appState.updateAccount(id: acc.id, name: name, groupId: gid)
                accountToEdit = nil
            })
        }
    }

    private func accountsIn(_ group: AccountGroup) -> [Account] {
        appState.data.accounts.filter { group.accounts.contains($0.id) }
    }
}

struct AboutSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("CryptoPnL Tracker").font(.title2)
            Text("A cryptocurrency portfolio tracking application with support for multiple users, accounts, and client tracking.")
                .multilineTextAlignment(.center)
                .font(.caption)
            Button("OK") { onDismiss() }
        }
        .padding(32)
        .frame(width: 360)
    }
}

struct ExportSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Export trades as JSON to a file of your choice.").font(.caption)
            Button("Choose file…") {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.json]
                panel.nameFieldStringValue = "trades_\(appState.currentUser).json"
                if panel.runModal() == .OK, let url = panel.url {
                    struct ExportWrapper: Encodable { let trades: [Trade] }
                    if let data = try? JSONEncoder().encode(ExportWrapper(trades: appState.data.trades)) {
                        try? data.write(to: url)
                        appState.appendActivity("Exported trades to \(url.lastPathComponent)")
                    }
                }
                dismiss(); onDismiss()
            }
            Button("Cancel") { dismiss(); onDismiss() }
        }
        .padding(24)
    }

}

struct ImportSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Import trades from a JSON file (same format as export).").font(.caption)
            Button("Choose file…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.json]
                if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tradesArray = json["trades"] as? [[String: Any]] {
                    let decoder = JSONDecoder()
                    for t in tradesArray {
                        if let td = try? JSONSerialization.data(withJSONObject: t),
                           let trade = try? decoder.decode(Trade.self, from: td) {
                            if !appState.data.trades.contains(where: { $0.id == trade.id }) {
                                appState.data.trades.append(trade)
                            }
                        }
                    }
                    appState.save()
                    appState.recomputeMetrics()
                    appState.appendActivity("Imported trades from file")
                }
                dismiss(); onDismiss()
            }
            Button("Cancel") { dismiss(); onDismiss() }
        }
        .padding(24)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
