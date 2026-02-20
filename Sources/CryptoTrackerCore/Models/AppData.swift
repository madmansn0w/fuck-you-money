import Foundation

/// Root app data; matches Python get_default_data() / JSON structure.
/// Optional projections preserve round-trip with existing JSON.
public struct AppData: Codable, Equatable {
    public var trades: [Trade]
    public var settings: Settings
    public var account_groups: [AccountGroup]
    public var accounts: [Account]
    public var projections: [[String]]?

    public init(
        trades: [Trade] = [],
        settings: Settings = Settings(),
        account_groups: [AccountGroup] = [],
        accounts: [Account] = [],
        projections: [[String]]? = nil
    ) {
        self.trades = trades
        self.settings = settings
        self.account_groups = account_groups
        self.accounts = accounts
        self.projections = projections
    }
}
