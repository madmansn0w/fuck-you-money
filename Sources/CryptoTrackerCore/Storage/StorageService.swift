import Foundation

/// Default exchanges with maker/taker fees; matches Python DEFAULT_EXCHANGES.
public let defaultFeeStructure: FeeStructure = [
    "Bitstamp": MakerTakerFees(maker: 0.30, taker: 0.40),
    "Wallet": MakerTakerFees(maker: 0, taker: 0),
    "Binance": MakerTakerFees(maker: 0.10, taker: 0.10),
    "Binance Testnet": MakerTakerFees(maker: 0.10, taker: 0.10),
    "Coinbase Pro": MakerTakerFees(maker: 0.40, taker: 0.60),
    "Kraken": MakerTakerFees(maker: 0.25, taker: 0.40),
    "Bybit": MakerTakerFees(maker: 0.10, taker: 0.10),
    "Crypto.com": MakerTakerFees(maker: 0.25, taker: 0.50),
]

public struct StorageService {
    public let paths: DataPathProvider

    public init(paths: DataPathProvider) {
        self.paths = paths
    }

    // MARK: - Users

    public func loadUsers() -> [String] {
        let url = paths.usersFile
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let users = json["users"] as? [String] else {
            return ["Default"]
        }
        return users.isEmpty ? ["Default"] : users
    }

    public func saveUsers(_ users: [String]) throws {
        let url = paths.usersFile
        let json = ["users": users]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    public func addUser(_ username: String) -> Bool {
        var users = loadUsers()
        if users.contains(username) { return false }
        users.append(username)
        try? saveUsers(users)
        return true
    }

    public func deleteUser(_ username: String) -> Bool {
        var users = loadUsers()
        guard users.contains(username), users.count > 1 else { return false }
        users.removeAll { $0 == username }
        try? saveUsers(users)
        let url = paths.dataFile(for: username)
        try? FileManager.default.removeItem(at: url)
        return true
    }

    // MARK: - App data (with migrations)

    public func getDefaultData() -> AppData {
        let groupId = UUID().uuidString
        let accountId = UUID().uuidString
        let groups = [AccountGroup(id: groupId, name: "My Portfolio", accounts: [accountId])]
        let accounts = [Account(id: accountId, name: "Main", account_group_id: groupId, created_date: nil)]
        let settings = Settings(
            default_exchange: "Bitstamp",
            fee_structure: defaultFeeStructure,
            cost_basis_method: "average",
            is_client: false,
            client_percentage: 0,
            default_account_id: accountId
        )
        return AppData(trades: [], settings: settings, account_groups: groups, accounts: accounts)
    }

    public func loadData(username: String = "Default") throws -> AppData {
        // Migrate legacy crypto_data.json to crypto_data_default.json if needed
        if username == "Default" {
            let legacy = paths.legacyDataFile
            let userFile = paths.dataFile(for: username)
            if FileManager.default.fileExists(atPath: legacy.path), !FileManager.default.fileExists(atPath: userFile.path) {
                try? FileManager.default.copyItem(at: legacy, to: userFile)
            }
        }

        let url = paths.dataFile(for: username)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return getDefaultData()
        }

        let data = try Data(contentsOf: url)
        var appData = try JSONDecoder().decode(AppData.self, from: data)
        appData = migrateExchangeFees(appData)
        appData = migrateToAccountStructure(appData, username: username)
        ensureTradeIdsAndAccountIds(&appData)
        ensureSettingsDefaults(&appData)
        return appData
    }

    public func saveData(_ appData: AppData, username: String = "Default") throws {
        let url = paths.dataFile(for: username)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(appData)
        try data.write(to: url)
    }

    // MARK: - Price cache

    /// Returns a copy of the price cache with all keys uppercased (canonical form for lookups).
    /// When multiple keys map to the same uppercase key (e.g. "bnb" and "BNB"), the last value wins.
    public static func normalizePriceCacheKeys(_ cache: [String: [String: Any]]) -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        for (key, value) in cache {
            result[key.uppercased()] = value
        }
        return result
    }

    public func loadPriceCache() -> [String: [String: Any]] {
        let url = paths.priceCacheFile
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            return [:]
        }
        return json
    }

    public func savePriceCache(_ cache: [String: [String: Any]]) {
        let url = paths.priceCacheFile
        guard let data = try? JSONSerialization.data(withJSONObject: cache, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url)
    }

    // MARK: - Price history (daily prices per asset for correlation matrix)

    /// Loads price history: asset → (date "yyyy-MM-dd" → price). Used to build aligned return series.
    /// Inner values are parsed from JSON number (Int or Double).
    public func loadPriceHistory() -> [String: [String: Double]] {
        let url = paths.priceHistoryFile
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            return [:]
        }
        var result: [String: [String: Double]] = [:]
        for (asset, dates) in json {
            var prices: [String: Double] = [:]
            for (date, val) in dates {
                if let d = val as? Double { prices[date] = d }
                else if let i = val as? Int { prices[date] = Double(i) }
                else if let n = val as? NSNumber { prices[date] = n.doubleValue }
                else { continue }
            }
            if !prices.isEmpty { result[asset] = prices }
        }
        return result
    }

    /// Saves price history. Each asset's dates are typically trimmed to last N days (e.g. 365) before saving.
    public func savePriceHistory(_ history: [String: [String: Double]]) {
        let url = paths.priceHistoryFile
        guard let data = try? JSONSerialization.data(withJSONObject: history, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url)
    }

    // MARK: - Migrations

    private func migrateExchangeFees(_ data: AppData) -> AppData {
        var settings = data.settings
        var feeStruct: FeeStructure = [:]
        for (name, fees) in settings.fee_structure {
            feeStruct[name] = MakerTakerFees(maker: fees.maker, taker: fees.taker)
        }
        settings.fee_structure = feeStruct
        return AppData(trades: data.trades, settings: settings, account_groups: data.account_groups, accounts: data.accounts)
    }

    private func migrateToAccountStructure(_ data: AppData, username: String) -> AppData {
        var groups = data.account_groups
        var accounts = data.accounts
        var settings = data.settings
        var trades = data.trades

        if accounts.isEmpty {
            let groupId = UUID().uuidString
            let accountId = UUID().uuidString
            groups = [AccountGroup(id: groupId, name: "My Portfolio", accounts: [accountId])]
            accounts = [Account(id: accountId, name: "Main", account_group_id: groupId, created_date: nil)]
            settings.default_account_id = accountId
            for i in trades.indices {
                trades[i].account_id = accountId
            }
        }

        if settings.default_account_id == nil, let first = accounts.first {
            settings.default_account_id = first.id
        }
        return AppData(trades: trades, settings: settings, account_groups: groups, accounts: accounts, projections: data.projections)
    }

    private func ensureTradeIdsAndAccountIds(_ data: inout AppData) {
        let firstAccountId = data.accounts.first?.id
        for i in data.trades.indices {
            if data.trades[i].id.isEmpty {
                data.trades[i].id = UUID().uuidString
            }
            if data.trades[i].account_id == nil || data.trades[i].account_id?.isEmpty == true {
                data.trades[i].account_id = firstAccountId
            }
        }
    }

    private func ensureSettingsDefaults(_ data: inout AppData) {
        var s = data.settings
        if s.fee_structure["Bitstamp"] == nil { s.fee_structure["Bitstamp"] = MakerTakerFees(maker: 0.30, taker: 0.40) }
        if s.fee_structure["Wallet"] == nil { s.fee_structure["Wallet"] = MakerTakerFees(maker: 0, taker: 0) }
        if s.cost_basis_method.isEmpty { s.cost_basis_method = "average" }
        if s.profit_display_currency == nil || s.profit_display_currency?.isEmpty == true { s.profit_display_currency = "USD" }
        data.settings = s
    }
}
