import Foundation
import CryptoKit

/// Bitstamp REST API v2 implementation for balance, fee tier, 30d volume, and order placement.
public struct BitstampAPI: ExchangeAPI {
    public static let exchangeName = "Bitstamp"

    private let baseURL = "https://www.bitstamp.net/api/v2"
    private let host = "www.bitstamp.net"
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Private request helper

    private func privatePost(path: String, body: [String: String] = [:], apiKey: String, secret: String) async throws -> [String: Any] {
        let url = URL(string: baseURL + path)!
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        let nonce = UUID().uuidString.lowercased()
        let contentType = body.isEmpty ? "" : "application/x-www-form-urlencoded"
        let bodyString = body.isEmpty ? "" : body.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "&")

        let stringToSign = "BITSTAMP " + apiKey + "POST" + host + path + "" + contentType + nonce + timestamp + "v2" + bodyString
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key)
        let signatureHex = signature.map { String(format: "%02hhx", $0) }.joined().uppercased()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("BITSTAMP " + apiKey, forHTTPHeaderField: "X-Auth")
        request.setValue(signatureHex, forHTTPHeaderField: "X-Auth-Signature")
        request.setValue(nonce, forHTTPHeaderField: "X-Auth-Nonce")
        request.setValue(timestamp, forHTTPHeaderField: "X-Auth-Timestamp")
        request.setValue("v2", forHTTPHeaderField: "X-Auth-Version")
        if !body.isEmpty {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(bodyString.utf8)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ExchangeAPIError.network(underlying: NSError(domain: "Bitstamp", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
        }

        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if let code = json["response_code"] as? String {
            let explanation = (json["response_explanation"] as? String) ?? code
            if code.hasPrefix("403") || code == "API0001" || code == "API0008" {
                throw ExchangeAPIError.invalidCredentials
            }
            if code == "400.002" || code.hasPrefix("400.067") || code.hasPrefix("400.068") || http.statusCode == 429 {
                throw ExchangeAPIError.rateLimit
            }
            if code == "400.009" || code == "400.075" {
                throw ExchangeAPIError.insufficientBalance
            }
            throw ExchangeAPIError.exchange(explanation)
        }

        if http.statusCode != 200 {
            throw ExchangeAPIError.network(underlying: NSError(domain: "Bitstamp", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]))
        }
        return json
    }

    // MARK: - ExchangeAPI

    public func fetchBalances(apiKey: String, secret: String) async throws -> BalanceInfo {
        let json = try await privatePost(path: "/balance/", body: [:], apiKey: apiKey, secret: secret)
        var total: [String: Double] = [:]
        var available: [String: Double] = [:]
        for (key, value) in json {
            guard let str = value as? String, let num = Double(str) else { continue }
            if key.hasSuffix("_balance") {
                let asset = String(key.dropLast(8)).uppercased()
                total[asset] = num
            } else if key.hasSuffix("_available") {
                let asset = String(key.dropLast(10)).uppercased()
                available[asset] = num
            }
        }
        return BalanceInfo(totalByAsset: total, availableByAsset: available.isEmpty ? total : available)
    }

    public func fetchFeeTier(apiKey: String, secret: String) async throws -> FeeTierInfo {
        let json = try await privatePost(path: "/trading_fees/", body: [:], apiKey: apiKey, secret: secret)
        guard let fees = json["fees"] as? [[String: Any]],
              let first = fees.first,
              let maker = first["maker_fee"] as? String,
              let taker = first["taker_fee"] as? String else {
            return FeeTierInfo(makerPercent: 0.30, takerPercent: 0.40)
        }
        let makerPct = (Double(maker) ?? 0.003) * 100
        let takerPct = (Double(taker) ?? 0.004) * 100
        return FeeTierInfo(makerPercent: makerPct, takerPercent: takerPct)
    }

    public func fetch30DayVolume(apiKey: String, secret: String) async throws -> Double {
        // Bitstamp trading_fees may include volume; if not, return 0.
        let json = try await privatePost(path: "/trading_fees/", body: [:], apiKey: apiKey, secret: secret)
        if let vol = json["volume_30d"] as? Double { return vol }
        if let vol = json["volume_30d"] as? String, let d = Double(vol) { return d }
        return 0
    }

    public func placeOrder(apiKey: String, secret: String, params: OrderParams) async throws -> OrderResult {
        let market = bitstampMarket(params.symbol)
        let path = params.side == .buy ? "/buy/\(market)/" : "/sell/\(market)/"
        var body: [String: String] = ["amount": String(params.amount)]
        if params.orderType == .limit, let price = params.price {
            body["limit_price"] = String(price)
        }
        if params.orderType == .market {
            body["market_order_type"] = "1" // 1 = default market
        }
        switch params.timeInForce {
        case .ioc: body["time_in_force"] = "IOC"
        case .fok: body["time_in_force"] = "FOK"
        case .gtd:
            if let exp = params.expireTime {
                body["expire_time"] = String(Int64(exp.timeIntervalSince1970))
            }
        default: break
        }

        let json = try await privatePost(path: path, body: body, apiKey: apiKey, secret: secret)
        guard let orderId = json["id"] as? String ?? (json["id"] as? Int).map({ String($0) }) else {
            throw ExchangeAPIError.exchange((json["response_explanation"] as? String) ?? "Order failed")
        }
        return OrderResult(orderId: orderId)
    }

    private func bitstampMarket(_ symbol: String) -> String {
        let clean = symbol.replacingOccurrences(of: "/", with: "").lowercased()
        if clean == "btcusd" || clean == "btc" { return "btc_usd" }
        if clean == "ethusd" || clean == "eth" { return "eth_usd" }
        if clean.hasSuffix("usd"), clean.count > 3 {
            let idx = clean.index(clean.endIndex, offsetBy: -3)
            return String(clean[..<idx]) + "_usd"
        }
        return clean + "_usd"
    }
}
