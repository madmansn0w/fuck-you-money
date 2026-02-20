import Foundation

/// Trade type; matches Python TRADE_TYPES_* and JSON.
public enum TradeType: String, Codable, CaseIterable {
    case BUY
    case SELL
    case Holding
    case Transfer
    case Withdrawal
    case Deposit
}

/// A single trade record; keys match existing JSON for compatibility.
public struct Trade: Codable, Equatable, Identifiable {
    public var id: String
    public var date: String
    public var asset: String
    public var type: String
    public var price: Double
    public var quantity: Double
    public var exchange: String
    public var order_type: String
    public var fee: Double
    public var total_value: Double
    public var account_id: String?
    public var is_client_trade: Bool?
    public var client_name: String?
    public var client_percentage: Double?
    /// Optional source tag for API-originated trades (e.g. "crank" for Crank Crypto Bot).
    public var source: String?
    /// Optional strategy identifier for attribution (e.g. "grid_btcusdt").
    public var strategy_id: String?

    public init(
        id: String,
        date: String,
        asset: String,
        type: String,
        price: Double,
        quantity: Double,
        exchange: String,
        order_type: String,
        fee: Double,
        total_value: Double,
        account_id: String? = nil,
        is_client_trade: Bool? = nil,
        client_name: String? = nil,
        client_percentage: Double? = nil,
        source: String? = nil,
        strategy_id: String? = nil
    ) {
        self.id = id
        self.date = date
        self.asset = asset
        self.type = type
        self.price = price
        self.quantity = quantity
        self.exchange = exchange
        self.order_type = order_type
        self.fee = fee
        self.total_value = total_value
        self.account_id = account_id
        self.is_client_trade = is_client_trade
        self.client_name = client_name
        self.client_percentage = client_percentage
        self.source = source
        self.strategy_id = strategy_id
    }

    enum CodingKeys: String, CodingKey {
        case id, date, asset, type, price, quantity, exchange, order_type, fee, total_value
        case account_id
        case is_client_trade
        case client_name
        case client_percentage
        case source
        case strategy_id
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        date = try c.decode(String.self, forKey: .date)
        asset = try c.decode(String.self, forKey: .asset)
        type = try c.decode(String.self, forKey: .type)
        price = (try? c.decode(Double.self, forKey: .price)) ?? 0
        quantity = (try? c.decode(Double.self, forKey: .quantity)) ?? 0
        exchange = (try? c.decode(String.self, forKey: .exchange)) ?? ""
        order_type = (try? c.decode(String.self, forKey: .order_type)) ?? ""
        fee = (try? c.decode(Double.self, forKey: .fee)) ?? 0
        total_value = (try? c.decode(Double.self, forKey: .total_value)) ?? 0
        account_id = try? c.decode(String.self, forKey: .account_id)
        is_client_trade = try? c.decode(Bool.self, forKey: .is_client_trade)
        client_name = try? c.decode(String.self, forKey: .client_name)
        client_percentage = try? c.decode(Double.self, forKey: .client_percentage)
        source = try? c.decode(String.self, forKey: .source)
        strategy_id = try? c.decode(String.self, forKey: .strategy_id)
    }
}
