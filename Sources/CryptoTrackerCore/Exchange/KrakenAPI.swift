import Foundation
import CryptoKit

/// Kraken REST API implementation for balance, fee tier, 30d volume, and order placement.
public struct KrakenAPI: ExchangeAPI {
    public static let exchangeName = "Kraken"

    private let baseURL = "https://api.kraken.com"
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Private request helper

    private func privatePost(path: String, form: [String: String], apiKey: String, secret: String) async throws -> [String: Any] {
        let url = URL(string: baseURL + path)!
        let nonce = String(Int64(Date().timeIntervalSince1970 * 1000))
        var formWithNonce = form
        formWithNonce["nonce"] = nonce
        let postData = formWithNonce.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "&")

        let message = path + SHA256.hash(data: Data((nonce + postData).utf8)).map { String(format: "%02x", $0) }.joined()
        guard let secretData = Data(base64Encoded: secret, options: .ignoreUnknownCharacters) else {
            throw ExchangeAPIError.invalidCredentials
        }
        let key = SymmetricKey(data: secretData)
        let signature = HMAC<SHA512>.authenticationCode(for: Data(message.utf8), using: key)
        let signatureBase64 = Data(signature).base64EncodedString()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "API-Key")
        request.setValue(signatureBase64, forHTTPHeaderField: "API-Sign")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(postData.utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ExchangeAPIError.network(underlying: NSError(domain: "Kraken", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])) }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let errors = json["error"] as? [String], !errors.isEmpty {
            let msg = errors.joined(separator: "; ")
            if msg.lowercased().contains("invalid key") || msg.lowercased().contains("authentication") {
                throw ExchangeAPIError.invalidCredentials
            }
            if msg.lowercased().contains("rate limit") || http.statusCode == 429 {
                throw ExchangeAPIError.rateLimit
            }
            throw ExchangeAPIError.exchange(msg)
        }

        if http.statusCode != 200 {
            throw ExchangeAPIError.network(underlying: NSError(domain: "Kraken", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]))
        }
        return json
    }

    // MARK: - ExchangeAPI

    public func fetchBalances(apiKey: String, secret: String) async throws -> BalanceInfo {
        let json = try await privatePost(path: "/0/private/Balance", form: [:], apiKey: apiKey, secret: secret)
        guard let result = json["result"] as? [String: String] else {
            throw ExchangeAPIError.exchange("Invalid balance response")
        }
        var total: [String: Double] = [:]
        for (asset, balance) in result {
            let norm = normalizeAsset(asset)
            total[norm] = Double(balance) ?? 0
        }
        // Kraken Balance returns "balance" (total); for "available" we'd need ExtendedBalance. Use total as available for simplicity; real available = total - on hold.
        return BalanceInfo(totalByAsset: total, availableByAsset: total)
    }

    public func fetchFeeTier(apiKey: String, secret: String) async throws -> FeeTierInfo {
        let json = try await privatePost(path: "/0/private/TradeVolume", form: ["pair": "XBTUSD"], apiKey: apiKey, secret: secret)
        guard let result = json["result"] as? [String: Any] else {
            throw ExchangeAPIError.exchange("Invalid trade volume response")
        }
        // fees = taker, fees_maker = maker (as decimal, e.g. 0.0026 = 0.26%)
        let taker = (result["fees"] as? [String: String])?["XBTUSD"] ?? (result["fees"] as? [String: Any])?.values.first as? String
        let maker = (result["fees_maker"] as? [String: String])?["XBTUSD"] ?? (result["fees_maker"] as? [String: Any])?.values.first as? String
        let takerPct = (Double(taker ?? "0.004") ?? 0.4) * 100
        let makerPct = (Double(maker ?? "0.0026") ?? 0.26) * 100
        return FeeTierInfo(makerPercent: makerPct, takerPercent: takerPct)
    }

    public func fetch30DayVolume(apiKey: String, secret: String) async throws -> Double {
        let json = try await privatePost(path: "/0/private/TradeVolume", form: ["pair": "XBTUSD"], apiKey: apiKey, secret: secret)
        guard let result = json["result"] as? [String: Any],
              let volume = result["volume"] as? Double else {
            return 0
        }
        return volume
    }

    public func placeOrder(apiKey: String, secret: String, params: OrderParams) async throws -> OrderResult {
        let pair = krakenPair(params.symbol)
        var form: [String: String] = [
            "pair": pair,
            "type": params.side == .buy ? "buy" : "sell",
            "ordertype": krakenOrderType(params.orderType),
            "volume": String(params.amount),
        ]
        if let price = params.price, params.orderType != .market {
            form["price"] = String(price)
        }
        if params.postOnly {
            form["postonly"] = "true"
        }
        switch params.timeInForce {
        case .ioc: form["timeinforce"] = "IOC"
        case .gtc: form["timeinforce"] = "GTC"
        case .gtd:
            form["timeinforce"] = "GTD"
            if let exp = params.expireTime {
                form["expiretm"] = String(Int64(exp.timeIntervalSince1970))
            }
        case .fok: form["timeinforce"] = "FOK"
        case .daily: form["timeinforce"] = "GTD"
        }
        if let stop = params.stopPrice {
            form["price2"] = String(stop)
        }
        if params.trailingOffset != nil, (params.orderType == .trailingStop || params.orderType == .trailingStopLimit) {
            form["misc"] = "trailing"
            form["oflags"] = "viqc"
        }

        let json = try await privatePost(path: "/0/private/AddOrder", form: form, apiKey: apiKey, secret: secret)
        guard let result = json["result"] as? [String: Any],
              let txid = (result["txid"] as? [String])?.first ?? result["txid"] as? String else {
            throw ExchangeAPIError.exchange((json["error"] as? [String])?.joined() ?? "Order failed")
        }
        let descr = (result["descr"] as? [String: String])?["order"]
        return OrderResult(orderId: txid, message: descr)
    }

    private func normalizeAsset(_ asset: String) -> String {
        if asset.hasPrefix("X") && asset != "XBT" && asset.count == 4 { return String(asset.dropFirst()) }
        if asset == "XBT" || asset == "XXBT" { return "BTC" }
        if asset == "ZUSD" || asset == "USD" { return "USD" }
        if asset.hasPrefix("Z") { return String(asset.dropFirst()) }
        return asset
    }

    private func krakenPair(_ symbol: String) -> String {
        let clean = symbol.replacingOccurrences(of: "/", with: "").uppercased()
        if clean == "BTCUSD" || clean == "XBTUSD" { return "XBTUSD" }
        if clean.hasPrefix("XBT") { return "XBT" + clean.dropFirst(3) }
        return clean
    }

    private func krakenOrderType(_ t: OrderType) -> String {
        switch t {
        case .market: return "market"
        case .limit: return "limit"
        case .stopLoss: return "stop-loss"
        case .stopLossLimit: return "stop-loss-limit"
        case .takeProfit: return "take-profit"
        case .takeProfitLimit: return "take-profit-limit"
        case .iceberg: return "limit" // Kraken iceberg via ordertype + leverage
        case .trailingStop: return "trailing-stop"
        case .trailingStopLimit: return "trailing-stop-limit"
        }
    }
}
