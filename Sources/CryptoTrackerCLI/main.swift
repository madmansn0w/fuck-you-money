import Foundation
import CryptoTrackerCore

func argValue(_ name: String, from args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func hasFlag(_ name: String, in args: [String]) -> Bool {
    args.contains(name)
}

/// Append today's price for each asset to price history and trim to last 365 days (for correlation matrix).
func recordPriceHistory(storage: StorageService, cache: [String: [String: Any]], assets: [String]) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let today = formatter.string(from: Date())
    var history = storage.loadPriceHistory()
    for asset in assets {
        let key = asset.uppercased()
        guard let entry = cache[key], let price = entry["price"] as? Double else { continue }
        var dates = history[key] ?? [:]
        dates[today] = price
        let sortedDates = dates.keys.sorted()
        if sortedDates.count > 365 {
            let toKeep = Set(sortedDates.suffix(365))
            dates = dates.filter { toKeep.contains($0.key) }
        }
        history[key] = dates
    }
    storage.savePriceHistory(history)
}

/// Notify the running Swift app to reload data: try POST /v1/refresh to local API first;
/// if that fails (e.g. API disabled), open cryptotracker://refresh via the system.
func notifyApp(apiPort: Int = 38472) {
    let url = URL(string: "http://127.0.0.1:\(apiPort)/v1/refresh")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 2
    let sem = DispatchSemaphore(value: 0)
    var useFallback = true
    URLSession.shared.dataTask(with: request) { _, response, _ in
        if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
            useFallback = false
        }
        sem.signal()
    }.resume()
    sem.wait()
    if useFallback {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["cryptotracker://refresh"]
        try? proc.run()
    }
}

func main() {
    let args = Array(ProcessInfo.processInfo.arguments.dropFirst())
    let dataDir = argValue("--data-dir", from: args).map { URL(fileURLWithPath: $0) }
    let pathProvider = dataDir.map { DataPathProvider(baseURL: $0) } ?? DataPathProvider.currentDirectory
    let storage = StorageService(paths: pathProvider)
    let user = argValue("--user", from: args) ?? "Default"

    if args.isEmpty || args.contains("--help") || args.contains("-h") {
        print("Usage: crypto-tracker-cli <command> [options]")
        print("Commands: list-trades, add-trade, export-trades, import-trades, portfolio, positions, refresh, restore-backup")
        print("Options: --user <name> (default: Default), --data-dir <path>, --notify-app [--api-port 38472]")
        print("  add-trade: --asset, --type, --quantity, --price [--fee 0] [--exchange] [--account-id] [--date]")
        print("  import-trades: --file <path>")
        print("  export-trades: [--output <path>]")
        print("  positions: [--output <path>] — per-asset positions as JSON (same as GET /v1/positions)")
        print("  restore-backup: --file <path> — restore users, data, and price history from a backup JSON")
        print("  --notify-app: after add-trade/import-trades/refresh, notify running app (HTTP API or URL scheme)")
        return
    }
    if args.contains("--version") || args.contains("-v") {
        print("crypto-tracker-cli 1.0.0")
        return
    }

    let command = args.first ?? ""
    let notifyAppAfter = hasFlag("--notify-app", in: args)
    let apiPort = Int(argValue("--api-port", from: args) ?? "38472") ?? 38472

    switch command {
    case "list-trades":
        do {
            let data = try storage.loadData(username: user)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let json = try encoder.encode(data.trades)
            print(String(data: json, encoding: .utf8) ?? "")
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }

    case "add-trade":
        guard let asset = argValue("--asset", from: args),
              let type = argValue("--type", from: args),
              let qStr = argValue("--quantity", from: args), let quantity = Double(qStr),
              let pStr = argValue("--price", from: args), let price = Double(pStr) else {
            fputs("add-trade requires: --asset, --type, --quantity, --price\n", stderr)
            exit(1)
        }
        let fee = Double(argValue("--fee", from: args) ?? "0") ?? 0
        let exchange = argValue("--exchange", from: args) ?? "Wallet"
        let accountId = argValue("--account-id", from: args)
        let totalValue = quantity * price
        let dateStr = argValue("--date", from: args) ?? {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f.string(from: Date())
        }()
        var data: AppData
        do {
            data = try storage.loadData(username: user)
        } catch {
            fputs("Error loading data: \(error)\n", stderr)
            exit(1)
        }
        let tradeId = UUID().uuidString
        let defaultAccountId = data.accounts.first?.id ?? accountId
        let trade = Trade(
            id: tradeId,
            date: dateStr,
            asset: asset,
            type: type,
            price: price,
            quantity: quantity,
            exchange: exchange,
            order_type: "",
            fee: fee,
            total_value: totalValue,
            account_id: accountId ?? defaultAccountId
        )
        data.trades.append(trade)
        do {
            try storage.saveData(data, username: user)
            print("Added trade \(tradeId)")
            if notifyAppAfter { notifyApp(apiPort: apiPort) }
        } catch {
            fputs("Error saving: \(error)\n", stderr)
            exit(1)
        }

    case "export-trades":
        do {
            let data = try storage.loadData(username: user)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let tradesData = try encoder.encode(data.trades)
            let tradesJson = try JSONSerialization.jsonObject(with: tradesData)
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let export: [String: Any] = ["trades": tradesJson, "export_date": f.string(from: Date())]
            let jsonData = try JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])
            let outPath = argValue("--output", from: args)
            if let path = outPath {
                try jsonData.write(to: URL(fileURLWithPath: path))
                print("Exported to \(path)")
            } else {
                print(String(data: jsonData, encoding: .utf8) ?? "")
            }
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }

    case "import-trades":
        guard let filePath = argValue("--file", from: args) else {
            fputs("import-trades requires --file <path>\n", stderr)
            exit(1)
        }
        do {
            let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let json = try JSONSerialization.jsonObject(with: fileData) as? [String: Any]
            guard let tradesJson = json?["trades"] as? [[String: Any]] else {
                fputs("Invalid file: expected 'trades' key\n", stderr)
                exit(1)
            }
            var data = try storage.loadData(username: user)
            let decoder = JSONDecoder()
            for var tradeDict in tradesJson {
                if tradeDict["id"] == nil { tradeDict["id"] = UUID().uuidString }
                if tradeDict["is_client_trade"] == nil { tradeDict["is_client_trade"] = false }
                if tradeDict["client_name"] == nil { tradeDict["client_name"] = "" }
                if tradeDict["client_percentage"] == nil { tradeDict["client_percentage"] = 0 }
                let tradeData = try JSONSerialization.data(withJSONObject: tradeDict)
                let trade = try decoder.decode(Trade.self, from: tradeData)
                data.trades.append(trade)
            }
            try storage.saveData(data, username: user)
            print("Imported \(tradesJson.count) trade(s)")
            if notifyAppAfter { notifyApp(apiPort: apiPort) }
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }

    case "portfolio":
        do {
            let data = try storage.loadData(username: user)
            let cacheBox = CacheBox(storage.loadPriceCache())
            let pricing = PricingService()
            let metrics = MetricsService()
            func getPrice(_ asset: String) -> Double? {
                pricing.getCurrentPriceSync(asset: asset, cacheBox: cacheBox, saveCache: { storage.savePriceCache($0) })
            }
            let result = metrics.computePortfolioMetrics(trades: data.trades, costBasisMethod: data.settings.cost_basis_method, getCurrentPrice: getPrice)
            storage.savePriceCache(cacheBox.value)
            print("Total value: $\(String(format: "%.2f", result.total_value))")
            print("Total P&L: $\(String(format: "%.2f", result.total_pnl))")
            print("ROI: \(String(format: "%.2f", result.roi_pct))%")
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }

    case "positions":
        do {
            let data = try storage.loadData(username: user)
            let cacheBox = CacheBox(storage.loadPriceCache())
            let pricing = PricingService()
            let metrics = MetricsService()
            func getPrice(_ asset: String) -> Double? {
                pricing.getCurrentPriceSync(asset: asset, cacheBox: cacheBox, saveCache: { storage.savePriceCache($0) })
            }
            let result = metrics.computePortfolioMetrics(trades: data.trades, costBasisMethod: data.settings.cost_basis_method, getCurrentPrice: getPrice)
            storage.savePriceCache(cacheBox.value)
            struct Position: Encodable { let asset: String; let qty: Double; let cost_basis: Double; let current_value: Double; let unrealized_pnl: Double; let realized_pnl: Double }
            let positions = result.per_asset
                .map { Position(asset: $0.key, qty: $0.value.units_held + $0.value.holding_qty, cost_basis: $0.value.cost_basis, current_value: $0.value.current_value, unrealized_pnl: $0.value.unrealized_pnl, realized_pnl: $0.value.realized_pnl) }
                .sorted { $0.asset < $1.asset }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let jsonData = try encoder.encode(positions)
            let outPath = argValue("--output", from: args)
            if let path = outPath {
                try jsonData.write(to: URL(fileURLWithPath: path))
                print("Wrote positions to \(path)")
            } else {
                print(String(data: jsonData, encoding: .utf8) ?? "[]")
            }
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }

    case "refresh":
        do {
            let data = try storage.loadData(username: user)
            let assets = Array(Set(data.trades.map(\.asset)).filter { $0 != "USD" && $0 != "USDC" && $0 != "USDT" })
            var cache = storage.loadPriceCache()
            let pricing = PricingService()
            var updated = 0
            let sem = DispatchSemaphore(value: 0)
            Task {
                for asset in assets {
                    let (price, pct) = await pricing.fetchPriceAnd24h(asset: asset)
                    if price != nil {
                        let f = DateFormatter()
                        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                        var entry: [String: Any] = ["price": price!, "timestamp": f.string(from: Date())]
                        if let pct = pct { entry["pct_change_24h"] = pct }
                        cache[asset.uppercased()] = entry
                        updated += 1
                    }
                }
                if updated > 0 {
                    var normalized: [String: [String: Any]] = [:]
                    for (k, v) in cache { normalized[k.uppercased()] = v }
                    storage.savePriceCache(normalized)
                    recordPriceHistory(storage: storage, cache: normalized, assets: assets)
                }
                print("Refreshed \(updated) price(s)")
                if notifyAppAfter { notifyApp(apiPort: apiPort) }
                sem.signal()
            }
            sem.wait()
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }

    case "restore-backup":
        guard let filePath = argValue("--file", from: args) else {
            fputs("restore-backup requires: --file <path>\n", stderr)
            exit(1)
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            struct BackupFile: Decodable {
                let exported_at: String
                let users: [String]
                let data_by_user: [String: AppData]
                let price_history: [String: [String: Double]]?
            }
            let payload = try JSONDecoder().decode(BackupFile.self, from: data)
            guard !payload.users.isEmpty else {
                fputs("Error: backup has no users\n", stderr)
                exit(1)
            }
            for username in payload.users {
                guard let appData = payload.data_by_user[username] else {
                    fputs("Error: backup missing data for user \(username)\n", stderr)
                    exit(1)
                }
                try storage.saveData(appData, username: username)
            }
            try storage.saveUsers(payload.users)
            storage.savePriceHistory(payload.price_history ?? [:])
            print("Restored from backup (exported \(payload.exported_at)): \(payload.users.count) user(s), price history included.")
            if notifyAppAfter { notifyApp(apiPort: apiPort) }
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }

    default:
        fputs("Unknown command: \(command)\n", stderr)
        exit(1)
    }
}

main()
