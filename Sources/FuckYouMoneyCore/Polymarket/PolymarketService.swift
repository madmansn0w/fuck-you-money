import Foundation

// MARK: - Gamma API response models (minimal for events + markets)

/// One prediction event from Polymarket Gamma API; can contain multiple markets.
public struct PolymarketEvent: Sendable {
    public let id: String
    public let slug: String
    public let title: String
    public let markets: [PolymarketMarket]
    /// Event page URL on Polymarket.
    public var eventURL: URL? {
        URL(string: "https://polymarket.com/event/\(slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug)")
    }
}

/// One market (e.g. Yes/No) under an event.
public struct PolymarketMarket: Sendable {
    public let id: String
    public let question: String
    public let outcomes: [String]
    public let outcomePrices: [Double]
    public let endDate: String?
    public let slug: String
    public let conditionId: String?
    /// Arb gap: 1 - yesPrice - noPrice when outcomes are ["Yes","No"]. Positive = opportunity.
    public var arbGap: Double? {
        guard outcomes.count == 2, outcomePrices.count == 2,
              let yesIdx = outcomes.firstIndex(of: "Yes"),
              let noIdx = outcomes.firstIndex(of: "No") else { return nil }
        let yesP = outcomePrices[yesIdx]
        let noP = outcomePrices[noIdx]
        let gap = 1.0 - yesP - noP
        return gap > 0 ? gap : nil
    }
    /// Best bid/ask from Gamma if present; otherwise nil (CLOB would provide live book).
    public let bestBid: Double?
    public let bestAsk: Double?
    public let spread: Double?
    /// CLOB token IDs for YES and NO (or multi-outcome). Used to fetch order book via CLOB API.
    public let clobTokenIds: [String]
}

/// Order book snapshot from Polymarket CLOB API (GET /book?token_id=...).
public struct OrderBookSnapshot: Sendable {
    public let tokenId: String
    public let bids: [(price: Double, size: Double)]
    public let asks: [(price: Double, size: Double)]
    public let tickSize: String?
    public let minOrderSize: String?
    /// Best bid price (highest buy). Nil if no bids.
    public var bestBid: Double? { bids.first?.price }
    /// Best ask price (lowest sell). Nil if no asks.
    public var bestAsk: Double? { asks.first?.price }
    /// Spread = bestAsk - bestBid. Nil if either side missing.
    public var spread: Double? {
        guard let bid = bestBid, let ask = bestAsk else { return nil }
        return ask - bid
    }
    /// Midpoint. Nil if either side missing.
    public var midpoint: Double? {
        guard let bid = bestBid, let ask = bestAsk else { return nil }
        return (bid + ask) / 2
    }
}

// MARK: - Service

/// Read-only Polymarket Gamma API client for events and markets. No auth required.
public struct PolymarketService: Sendable {
    private static let defaultGammaBase = "https://gamma-api.polymarket.com"
    private static let defaultClobBase = "https://clob.polymarket.com"
    private let gammaBase: String
    private let clobBase: String
    private let session: URLSession

    /// - Parameters:
    ///   - gammaBaseURL: Optional override (e.g. from Settings). Empty or nil uses default.
    ///   - clobBaseURL: Optional override for CLOB (order book). Empty or nil uses default.
    ///   - session: URLSession for requests.
    public init(gammaBaseURL: String? = nil, clobBaseURL: String? = nil, session: URLSession = .shared) {
        let g = (gammaBaseURL?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 }
        self.gammaBase = g ?? Self.defaultGammaBase
        let c = (clobBaseURL?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 }
        self.clobBase = c ?? Self.defaultClobBase
        self.session = session
    }

    /// Fetches events from Gamma API with optional slug filter. Returns decoded events or empty on failure.
    public func fetchEvents(
        active: Bool = true,
        closed: Bool = false,
        limit: Int = 100,
        slugContains: String? = nil,
        order: String? = "volume_24hr",
        ascending: Bool = false
    ) async -> [PolymarketEvent] {
        var comp = URLComponents(string: "\(gammaBase)/events")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "active", value: active ? "true" : "false"),
            URLQueryItem(name: "closed", value: closed ? "true" : "false"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let slug = slugContains, !slug.isEmpty {
            items.append(URLQueryItem(name: "slug_contains", value: slug))
        }
        if let o = order {
            items.append(URLQueryItem(name: "order", value: o))
            items.append(URLQueryItem(name: "ascending", value: ascending ? "true" : "false"))
        }
        comp.queryItems = items
        guard let url = comp.url else { return [] }
        do {
            let (data, _) = try await session.data(from: url)
            return Self.decodeEvents(from: data)
        } catch {
            return []
        }
    }

    /// Fetches crypto-related events by requesting with slug_contains for common terms and merging. Limits to active, non-closed.
    public func fetchCryptoEvents(limitPerQuery: Int = 50) async -> [PolymarketEvent] {
        let terms = ["bitcoin", "crypto", "ethereum", "btc", "eth"]
        var seenIds = Set<String>()
        var result: [PolymarketEvent] = []
        for term in terms {
            let events = await fetchEvents(active: true, closed: false, limit: limitPerQuery, slugContains: term)
            for e in events {
                if seenIds.insert(e.id).inserted {
                    result.append(e)
                }
            }
        }
        // Also fetch by volume and filter client-side for title/slug containing any keyword (catches "Bitcoin", "Ethereum", etc.)
        let fallback = await fetchEvents(active: true, closed: false, limit: 100, slugContains: nil, order: "volume_24hr", ascending: false)
        let keywords = ["bitcoin", "crypto", "ethereum", "btc", "eth", "solana", "sol", "polygon", "matic"]
        for e in fallback where !seenIds.contains(e.id) {
            let lower = (e.title + " " + e.slug).lowercased()
            if keywords.contains(where: { lower.contains($0) }) && seenIds.insert(e.id).inserted {
                result.append(e)
            }
        }
        return result.sorted { ($0.title.lowercased()) < ($1.title.lowercased()) }
    }

    /// Fetches order book for a single token from CLOB API. Returns nil on failure.
    public func fetchOrderBook(tokenId: String) async -> OrderBookSnapshot? {
        var comp = URLComponents(string: "\(clobBase)/book")!
        comp.queryItems = [URLQueryItem(name: "token_id", value: tokenId)]
        guard let url = comp.url else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            return Self.decodeOrderBook(tokenId: tokenId, from: data)
        } catch {
            return nil
        }
    }

    /// Decodes CLOB /book response into OrderBookSnapshot.
    public static func decodeOrderBook(tokenId: String, from data: Data) -> OrderBookSnapshot? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func parseLevels(_ key: String) -> [(Double, Double)] {
            guard let arr = json[key] as? [[String: Any]] else { return [] }
            return arr.compactMap { level -> (Double, Double)? in
                guard let p = (level["price"] as? String).flatMap({ Double($0) }) ?? (level["price"] as? NSNumber)?.doubleValue,
                      let s = (level["size"] as? String).flatMap({ Double($0) }) ?? (level["size"] as? NSNumber)?.doubleValue else { return nil }
                return (p, s)
            }
        }
        let bids = parseLevels("bids")
        let asks = parseLevels("asks")
        let tickSize = json["tick_size"] as? String
        let minOrderSize = json["min_order_size"] as? String
        return OrderBookSnapshot(tokenId: tokenId, bids: bids, asks: asks, tickSize: tickSize, minOrderSize: minOrderSize)
    }

    /// Decodes Gamma API events JSON array into [PolymarketEvent].
    public static func decodeEvents(from data: Data) -> [PolymarketEvent] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return json.compactMap { eventDict -> PolymarketEvent? in
            guard let id = eventDict["id"] as? String,
                  let slug = eventDict["slug"] as? String,
                  let title = eventDict["title"] as? String else { return nil }
            let marketsJson = eventDict["markets"] as? [[String: Any]] ?? []
            let markets = marketsJson.compactMap { PolymarketMarket(from: $0) }
            return PolymarketEvent(id: id, slug: slug, title: title, markets: markets)
        }
    }
}

// MARK: - Market decoding from Gamma payload

extension PolymarketMarket {
    /// Parses a single market from Gamma API market object.
    init?(from json: [String: Any]) {
        guard let id = json["id"] as? String,
              let question = json["question"] as? String,
              let slug = json["slug"] as? String else { return nil }
        let outcomes: [String]
        if let outStr = json["outcomes"] as? String,
           let data = outStr.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            outcomes = arr
        } else if let arr = json["outcomes"] as? [String] {
            outcomes = arr
        } else {
            outcomes = ["Yes", "No"]
        }
        let prices: [Double]
        if let priceStr = json["outcomePrices"] as? String,
           let data = priceStr.data(using: .utf8),
           let strArr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            prices = strArr.compactMap { Double($0) }
        } else if let arr = json["outcomePrices"] as? [String] {
            prices = arr.compactMap { Double($0) }
        } else if let arr = json["outcomePrices"] as? [Double] {
            prices = arr
        } else {
            prices = []
        }
        let endDate = json["endDate"] as? String
        let conditionId = json["conditionId"] as? String
        let bestBid = (json["bestBid"] as? NSNumber)?.doubleValue
        let bestAsk = (json["bestAsk"] as? NSNumber)?.doubleValue
        let spread = (json["spread"] as? NSNumber)?.doubleValue
        var clobTokenIds: [String] = []
        if let str = json["clobTokenIds"] as? String, let data = str.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            clobTokenIds = arr
        }
        self.init(
            id: id,
            question: question,
            outcomes: outcomes.isEmpty ? ["Yes", "No"] : outcomes,
            outcomePrices: prices,
            endDate: endDate,
            slug: slug,
            conditionId: conditionId,
            bestBid: bestBid,
            bestAsk: bestAsk,
            spread: spread,
            clobTokenIds: clobTokenIds
        )
    }
}
