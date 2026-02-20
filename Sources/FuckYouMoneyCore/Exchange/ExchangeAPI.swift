import Foundation

// MARK: - Shared types for exchange integration

/// Order side: buy or sell.
public enum OrderSide: String, CaseIterable {
    case buy
    case sell
}

/// Order type; not all exchanges support all types.
public enum OrderType: String, CaseIterable {
    case market
    case limit
    case stopLoss = "stop_loss"
    case stopLossLimit = "stop_loss_limit"
    case takeProfit = "take_profit"
    case takeProfitLimit = "take_profit_limit"
    case iceberg
    case trailingStop = "trailing_stop"
    case trailingStopLimit = "trailing_stop_limit"
}

/// Time in force for orders.
public enum TimeInForce: String, CaseIterable {
    case gtc = "GTC"  // Good-Til-Cancelled
    case fok = "FOK"  // Fill-Or-Kill
    case ioc = "IOC"  // Immediate-Or-Cancel
    case gtd = "GTD"  // Good-Til-Date
    case daily = "Daily"
}

/// Parameters for placing an order. Fields required depend on order type.
public struct OrderParams {
    public var side: OrderSide
    public var orderType: OrderType
    public var symbol: String  // e.g. "BTC/USD", "btcusd"
    public var amount: Double
    public var price: Double?  // nil for market
    public var stopPrice: Double?  // for stop/trailing
    public var postOnly: Bool
    public var timeInForce: TimeInForce
    public var expireTime: Date?  // for GTD
    public var visibleAmount: Double?  // for iceberg (display size)
    public var trailingOffset: Double?  // for trailing stop (amount or percent; exchange-specific)
    public var oso: Bool  // One-Cancels-Other / linked order (placeholder)

    public init(
        side: OrderSide,
        orderType: OrderType,
        symbol: String,
        amount: Double,
        price: Double? = nil,
        stopPrice: Double? = nil,
        postOnly: Bool = false,
        timeInForce: TimeInForce = .gtc,
        expireTime: Date? = nil,
        visibleAmount: Double? = nil,
        trailingOffset: Double? = nil,
        oso: Bool = false
    ) {
        self.side = side
        self.orderType = orderType
        self.symbol = symbol
        self.amount = amount
        self.price = price
        self.stopPrice = stopPrice
        self.postOnly = postOnly
        self.timeInForce = timeInForce
        self.expireTime = expireTime
        self.visibleAmount = visibleAmount
        self.trailingOffset = trailingOffset
        self.oso = oso
    }
}

/// Result of a placed order.
public struct OrderResult {
    public var orderId: String
    public var clientOrderId: String?
    public var message: String?

    public init(orderId: String, clientOrderId: String? = nil, message: String? = nil) {
        self.orderId = orderId
        self.clientOrderId = clientOrderId
        self.message = message
    }
}

/// Balance info: total and available per asset.
public struct BalanceInfo {
    public var totalByAsset: [String: Double]
    public var availableByAsset: [String: Double]

    public init(totalByAsset: [String: Double] = [:], availableByAsset: [String: Double] = [:]) {
        self.totalByAsset = totalByAsset
        self.availableByAsset = availableByAsset
    }
}

/// Fee tier from exchange (maker/taker percentages).
public struct FeeTierInfo {
    public var makerPercent: Double
    public var takerPercent: Double

    public init(makerPercent: Double, takerPercent: Double) {
        self.makerPercent = makerPercent
        self.takerPercent = takerPercent
    }
}

/// Exchange API protocol for live trading (Kraken, Bitstamp).
public protocol ExchangeAPI {
    /// Human-readable exchange name (e.g. "Kraken", "Bitstamp").
    static var exchangeName: String { get }

    /// Fetch total and available balances. Asset keys are normalized (e.g. "BTC", "USD").
    func fetchBalances(apiKey: String, secret: String) async throws -> BalanceInfo

    /// Fetch current fee tier (maker/taker in percent).
    func fetchFeeTier(apiKey: String, secret: String) async throws -> FeeTierInfo

    /// Fetch 30-day trading volume in USD (or quote currency).
    func fetch30DayVolume(apiKey: String, secret: String) async throws -> Double

    /// Place an order. Throws on invalid params or exchange error.
    func placeOrder(apiKey: String, secret: String, params: OrderParams) async throws -> OrderResult
}

/// Errors thrown by exchange API implementations.
public enum ExchangeAPIError: Error, LocalizedError {
    case invalidCredentials
    case network(underlying: Error)
    case rateLimit
    case insufficientBalance
    case invalidOrder(String)
    case exchange(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Invalid API key or secret."
        case .network(let e): return "Network error: \(e.localizedDescription)"
        case .rateLimit: return "Rate limit exceeded. Try again later."
        case .insufficientBalance: return "Insufficient balance for this order."
        case .invalidOrder(let msg): return "Invalid order: \(msg)"
        case .exchange(let msg): return msg
        }
    }
}
