import Foundation

/// Provides file paths for users, per-user data, and price cache.
/// Use a custom base URL for CLI/dev (e.g. repo root) or nil for app container.
public struct DataPathProvider {
    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// users.json path
    public var usersFile: URL { baseURL.appendingPathComponent("users.json") }

    /// crypto_data_{sanitized_username}.json
    public func dataFile(for username: String) -> URL {
        let safe = username.lowercased().replacingOccurrences(of: " ", with: "_")
        return baseURL.appendingPathComponent("crypto_data_\(safe).json")
    }

    /// Legacy single data file (for migration from Python)
    public var legacyDataFile: URL { baseURL.appendingPathComponent("crypto_data.json") }

    public var priceCacheFile: URL { baseURL.appendingPathComponent("price_cache.json") }

    /// Daily price history per asset for correlation (date "yyyy-MM-dd" → price). Used to build return series.
    public var priceHistoryFile: URL { baseURL.appendingPathComponent("price_history.json") }

    /// Default base = current directory (CLI/repo); app can override with Application Support.
    public static var currentDirectory: DataPathProvider {
        DataPathProvider(baseURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }
}
