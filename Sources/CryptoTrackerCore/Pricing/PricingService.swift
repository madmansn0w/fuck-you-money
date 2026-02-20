import Foundation

/// Per-asset market data from CoinGecko (price, volume, cap, supply, performance).
/// Used by the Assets tab for 24h volume, market cap, FDV, circulating supply, and period returns.
public struct AssetMarketData {
    public var price: Double
    public var priceChange24h: Double?
    public var priceChangePct24h: Double?
    /// 24h trading volume in USD.
    public var volume24h: Double?
    public var marketCap: Double?
    public var fullyDilutedValuation: Double?
    public var circulatingSupply: Double?
    /// Volume / market cap (nil if marketCap missing or zero).
    public var volumeToMarketCap: Double? {
        guard let v = volume24h, let m = marketCap, m > 0 else { return nil }
        return v / m
    }
    /// Performance: % change over period (from CoinGecko price_change_percentage_*_in_currency usd).
    public var pct7d: Double?
    public var pct14d: Double?
    public var pct30d: Double?
    public var pct60d: Double?
    public var pct200d: Double?
    public var pct1y: Double?
    /// Full name (e.g. "Bitcoin") from CoinGecko.
    public var name: String?
    /// Short description (English); may be truncated in UI.
    public var assetDescription: String?
    /// First homepage URL from CoinGecko.
    public var homepage: String?
    /// Community sentiment: votes up % (0–100). Used for Technicals label.
    public var sentimentVotesUpPct: Double?
    /// Community sentiment: votes down % (0–100).
    public var sentimentVotesDownPct: Double?
}

/// CoinGecko asset id mapping; matches Python COINGECKO_ASSET_IDS.
public let coingeckoAssetIds: [String: String] = [
    "BTC": "bitcoin",
    "ETH": "ethereum",
    "BNB": "binancecoin",
    "DENT": "dent",
    "ADA": "cardano",
    "SOL": "solana",
    "XRP": "ripple",
    "DOT": "polkadot",
    "DOGE": "dogecoin",
    "MATIC": "matic-network",
    "AVAX": "avalanche-2",
    "LINK": "chainlink",
    "UNI": "uniswap",
    "ATOM": "cosmos",
    "LTC": "litecoin",
    "ALGO": "algorand",
]

private let coingeckoURL = URL(string: "https://api.coingecko.com/api/v3/simple/price")!

/// CoinGecko coin detail endpoint (market_data: price, volume, mcap, supply, % changes).
private func coingeckoCoinURL(coinId: String) -> URL? {
    var comp = URLComponents(string: "https://api.coingecko.com/api/v3/coins/\(coinId)")!
    comp.queryItems = [
        URLQueryItem(name: "localization", value: "false"),
        URLQueryItem(name: "tickers", value: "false"),
        URLQueryItem(name: "community_data", value: "false"),
        URLQueryItem(name: "developer_data", value: "false"),
        URLQueryItem(name: "sparkline", value: "false"),
    ]
    return comp.url
}

/// CoinGecko history endpoint: date format dd-mm-yyyy.
private func coingeckoHistoryURL(coinId: String, date: Date) -> URL? {
    let cal = Calendar.current
    let day = cal.component(.day, from: date)
    let month = cal.component(.month, from: date)
    let year = cal.component(.year, from: date)
    let dateStr = String(format: "%02d-%02d-%04d", day, month, year)
    var comp = URLComponents(string: "https://api.coingecko.com/api/v3/coins/\(coinId)/history")!
    comp.queryItems = [URLQueryItem(name: "date", value: dateStr)]
    return comp.url
}

public struct PricingService {
    public init() {}

    /// Fetch historical USD price for a given day (for benchmark vs BTC). Returns nil if asset unsupported or fetch fails.
    public func fetchHistoricalPrice(asset: String, date: Date) async -> Double? {
        let upper = asset.uppercased()
        if upper == "USDC" || upper == "USDT" { return 1.0 }
        let coinId = coingeckoAssetIds[upper] ?? upper.lowercased()
        guard let url = coingeckoHistoryURL(coinId: coinId, date: date) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let marketData = json["market_data"] as? [String: Any],
                  let current = marketData["current_price"] as? [String: Any],
                  let price = current["usd"] as? Double else { return nil }
            return price
        } catch {
            return nil
        }
    }

    /// Fetch current price and 24h % change. USDC/USDT return (1.0, 0.0).
    public func fetchPriceAnd24h(asset: String) async -> (price: Double?, pct24h: Double?) {
        let upper = (asset).uppercased()
        if upper == "USDC" || upper == "USDT" { return (1.0, 0.0) }
        let coinId = coingeckoAssetIds[upper] ?? upper.lowercased()
        var comp = URLComponents(url: coingeckoURL, resolvingAgainstBaseURL: false)!
        comp.queryItems = [
            URLQueryItem(name: "ids", value: coinId),
            URLQueryItem(name: "vs_currencies", value: "usd"),
            URLQueryItem(name: "include_24hr_change", value: "true"),
        ]
        guard let url = comp.url else { return (nil, nil) }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let coin = json[coinId] as? [String: Any],
                  let price = coin["usd"] as? Double else { return (nil, nil) }
            let pct = (coin["usd_24h_change"] as? Double) ?? (coin["price_change_percentage_24h_in_currency"] as? Double)
            return (price, pct)
        } catch {
            return (nil, nil)
        }
    }

    /// Fetch full market data for an asset (price, 24h volume, market cap, FDV, supply, 7d/30d/1y %). USDC/USDT return minimal data.
    public func fetchAssetMarketData(asset: String) async -> AssetMarketData? {
        let upper = asset.uppercased()
        if upper == "USDC" || upper == "USDT" {
            return AssetMarketData(price: 1.0, priceChange24h: nil, priceChangePct24h: 0, volume24h: nil, marketCap: nil, fullyDilutedValuation: nil, circulatingSupply: nil, pct7d: nil, pct14d: nil, pct30d: nil, pct60d: nil, pct200d: nil, pct1y: nil, name: nil, assetDescription: nil, homepage: nil, sentimentVotesUpPct: nil, sentimentVotesDownPct: nil)
        }
        let coinId = coingeckoAssetIds[upper] ?? upper.lowercased()
        guard let url = coingeckoCoinURL(coinId: coinId) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let marketData = json["market_data"] as? [String: Any],
                  let currentPrice = marketData["current_price"] as? [String: Any],
                  let price = currentPrice["usd"] as? Double else { return nil }
            let priceChange24h = marketData["price_change_24h_in_currency"] as? [String: Any]
            let priceChange24hUsd = priceChange24h?["usd"] as? Double
            let pct24h = (marketData["price_change_percentage_24h_in_currency"] as? [String: Any])?["usd"] as? Double
                ?? marketData["price_change_percentage_24h"] as? Double
            let totalVol = marketData["total_volume"] as? [String: Any]
            let volume24h = totalVol?["usd"] as? Double
            let mcap = marketData["market_cap"] as? [String: Any]
            let marketCap = mcap?["usd"] as? Double
            let fdv = marketData["fully_diluted_valuation"] as? [String: Any]
            let fullyDilutedValuation = fdv?["usd"] as? Double
            let circulatingSupply = marketData["circulating_supply"] as? Double
            func pct(_ key: String) -> Double? {
                (marketData[key] as? [String: Any])?["usd"] as? Double ?? marketData[key] as? Double
            }
            let name = json["name"] as? String
            let descObj = json["description"] as? [String: String]
            let assetDescription = descObj?["en"]
            let links = json["links"] as? [String: Any]
            let homepageArr = links?["homepage"] as? [String]
            let homepage = homepageArr?.first.flatMap { s in s.isEmpty ? nil : s }
            let sentimentVotesUpPct = json["sentiment_votes_up_percentage"] as? Double
            let sentimentVotesDownPct = json["sentiment_votes_down_percentage"] as? Double
            return AssetMarketData(
                price: price,
                priceChange24h: priceChange24hUsd,
                priceChangePct24h: pct24h,
                volume24h: volume24h,
                marketCap: marketCap,
                fullyDilutedValuation: fullyDilutedValuation,
                circulatingSupply: circulatingSupply,
                pct7d: pct("price_change_percentage_7d_in_currency"),
                pct14d: pct("price_change_percentage_14d_in_currency"),
                pct30d: pct("price_change_percentage_30d_in_currency"),
                pct60d: pct("price_change_percentage_60d_in_currency"),
                pct200d: pct("price_change_percentage_200d_in_currency"),
                pct1y: pct("price_change_percentage_1y_in_currency"),
                name: name,
                assetDescription: assetDescription,
                homepage: homepage,
                sentimentVotesUpPct: sentimentVotesUpPct,
                sentimentVotesDownPct: sentimentVotesDownPct
            )
        } catch {
            return nil
        }
    }

    /// Get price from cache if present and fresh; otherwise fetch and update cache.
    public func getCurrentPrice(
        asset: String,
        cache: inout [String: [String: Any]],
        saveCache: ([String: [String: Any]]) -> Void,
        maxAgeMinutes: Double = 5.0
    ) async -> Double? {
        let upper = asset.uppercased()
        if upper == "USDC" || upper == "USDT" { return 1.0 }
        if let entry = cache[upper],
           let ts = entry["timestamp"] as? String,
           let price = entry["price"] as? Double {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let date = formatter.date(from: ts), Date().timeIntervalSince(date) / 60 < maxAgeMinutes {
                return price
            }
        }
        let (price, pct24h) = await fetchPriceAnd24h(asset: asset)
        guard let price = price else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var entry: [String: Any] = ["price": price, "timestamp": formatter.string(from: Date())]
        if let pct = pct24h { entry["pct_change_24h"] = pct }
        cache[upper] = entry
        saveCache(cache)
        return price
    }

    /// Synchronous wrapper for CLI: pass a box that holds the cache; after return, read updated cache from the box.
    public func getCurrentPriceSync(
        asset: String,
        cacheBox: CacheBox,
        saveCache: @escaping ([String: [String: Any]]) -> Void
    ) -> Double? {
        var result: Double?
        let sem = DispatchSemaphore(value: 0)
        Task {
            result = await getCurrentPrice(asset: asset, cache: &cacheBox.value, saveCache: saveCache)
            sem.signal()
        }
        sem.wait()
        return result
    }
}

/// Thread-safe box for passing cache in/out of async code from sync context.
public final class CacheBox {
    public var value: [String: [String: Any]]
    public init(_ value: [String: [String: Any]] = [:]) {
        self.value = value
    }
}
