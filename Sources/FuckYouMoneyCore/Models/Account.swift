import Foundation

public struct AccountGroup: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var accounts: [String]

    public init(id: String, name: String, accounts: [String]) {
        self.id = id
        self.name = name
        self.accounts = accounts
    }
}

public struct Account: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var account_group_id: String?
    public var created_date: String?

    public init(id: String, name: String, account_group_id: String? = nil, created_date: String? = nil) {
        self.id = id
        self.name = name
        self.account_group_id = account_group_id
        self.created_date = created_date
    }
}
