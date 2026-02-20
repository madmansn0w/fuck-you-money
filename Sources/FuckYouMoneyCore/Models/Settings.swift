import Foundation

/// Fee structure: exchange name -> maker/taker percentages.
public typealias FeeStructure = [String: MakerTakerFees]

public struct MakerTakerFees: Codable, Equatable {
    public var maker: Double
    public var taker: Double

    public init(maker: Double, taker: Double) {
        self.maker = maker
        self.taker = taker
    }
}

public enum CostBasisMethod: String, Codable, CaseIterable {
    case fifo
    case lifo
    case average
}

/// Settings object; keys match existing JSON.
public struct Settings: Codable, Equatable {
    public var default_exchange: String
    public var fee_structure: FeeStructure
    public var cost_basis_method: String
    public var is_client: Bool
    public var client_percentage: Double
    public var default_account_id: String?
    /// "USD" or "BTC"; used for transactions table Profit column. Default "USD".
    public var profit_display_currency: String?
    public var tab_order: [String]?
    public var window_geometry: String?
    public var pane_positions: [Int]?
    /// Exchange names for which API keys are configured (keys stored in Keychain only).
    public var exchange_api_configured: [String]

    public init(
        default_exchange: String = "Bitstamp",
        fee_structure: FeeStructure = [:],
        cost_basis_method: String = "average",
        is_client: Bool = false,
        client_percentage: Double = 0,
        default_account_id: String? = nil,
        profit_display_currency: String? = nil,
        tab_order: [String]? = nil,
        window_geometry: String? = nil,
        pane_positions: [Int]? = nil,
        exchange_api_configured: [String] = []
    ) {
        self.default_exchange = default_exchange
        self.fee_structure = fee_structure
        self.cost_basis_method = cost_basis_method
        self.is_client = is_client
        self.client_percentage = client_percentage
        self.default_account_id = default_account_id
        self.profit_display_currency = profit_display_currency
        self.tab_order = tab_order
        self.window_geometry = window_geometry
        self.pane_positions = pane_positions
        self.exchange_api_configured = exchange_api_configured
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        default_exchange = try c.decode(String.self, forKey: .default_exchange)
        fee_structure = try c.decode(FeeStructure.self, forKey: .fee_structure)
        cost_basis_method = try c.decode(String.self, forKey: .cost_basis_method)
        is_client = try c.decode(Bool.self, forKey: .is_client)
        client_percentage = try c.decode(Double.self, forKey: .client_percentage)
        default_account_id = try c.decodeIfPresent(String.self, forKey: .default_account_id)
        profit_display_currency = try c.decodeIfPresent(String.self, forKey: .profit_display_currency)
        tab_order = try c.decodeIfPresent([String].self, forKey: .tab_order)
        window_geometry = try c.decodeIfPresent(String.self, forKey: .window_geometry)
        pane_positions = try c.decodeIfPresent([Int].self, forKey: .pane_positions)
        exchange_api_configured = try c.decodeIfPresent([String].self, forKey: .exchange_api_configured) ?? []
    }
}
