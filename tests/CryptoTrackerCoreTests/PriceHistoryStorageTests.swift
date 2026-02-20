import XCTest
@testable import CryptoTrackerCore

/// Tests for price history load/save (used for correlation matrix).
final class PriceHistoryStorageTests: XCTestCase {

    func testSaveAndLoadPriceHistory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let paths = DataPathProvider(baseURL: tempDir)
        let storage = StorageService(paths: paths)

        let history: [String: [String: Double]] = [
            "BTC": ["2025-01-01": 42_000, "2025-01-02": 43_000, "2025-01-03": 41_500],
            "ETH": ["2025-01-01": 2_200, "2025-01-02": 2_250, "2025-01-03": 2_180]
        ]
        storage.savePriceHistory(history)
        let loaded = storage.loadPriceHistory()
        XCTAssertEqual(Set(loaded.keys), Set(history.keys))
        XCTAssertEqual(loaded["BTC"]?["2025-01-01"], 42_000)
        XCTAssertEqual(loaded["BTC"]?["2025-01-02"], 43_000)
        XCTAssertEqual(loaded["ETH"]?["2025-01-01"], 2_200)
    }

    func testLoadPriceHistoryMissingFileReturnsEmpty() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let paths = DataPathProvider(baseURL: tempDir)
        let storage = StorageService(paths: paths)
        let loaded = storage.loadPriceHistory()
        XCTAssertTrue(loaded.isEmpty)
    }
}
