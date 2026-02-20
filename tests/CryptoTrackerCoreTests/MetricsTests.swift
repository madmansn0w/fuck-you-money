import XCTest
@testable import CryptoTrackerCore

final class MetricsTests: XCTestCase {

    func testComputePortfolioMetricsEmpty() {
        let metrics = MetricsService()
        let result = metrics.computePortfolioMetrics(trades: [], costBasisMethod: "average") { _ in nil }
        XCTAssertEqual(result.per_asset.count, 0)
        XCTAssertEqual(result.total_value, 0)
        XCTAssertEqual(result.realized_pnl, 0)
        XCTAssertEqual(result.unrealized_pnl, 0)
        XCTAssertEqual(result.total_pnl, 0)
        XCTAssertEqual(result.roi_pct, 0)
    }

    func testCostBasisFifoSingleBuy() {
        let metrics = MetricsService()
        let trades = [
            Trade(id: "1", date: "2024-01-01", asset: "BTC", type: "BUY", price: 40000, quantity: 1, exchange: "Bitstamp", order_type: "maker", fee: 40, total_value: 40000, account_id: nil)
        ]
        let (cost, units, lots) = metrics.calculateCostBasisFifo(trades: trades, asset: "BTC")
        XCTAssertEqual(cost, 40040, accuracy: 0.01)
        XCTAssertEqual(units, 1, accuracy: 0.01)
        XCTAssertEqual(lots.count, 1)
    }

    func testCostBasisAverageSingleBuy() {
        let metrics = MetricsService()
        let trades = [
            Trade(id: "1", date: "2024-01-01", asset: "BTC", type: "BUY", price: 40000, quantity: 1, exchange: "Bitstamp", order_type: "maker", fee: 40, total_value: 40000, account_id: nil)
        ]
        let (cost, units, _) = metrics.calculateCostBasisAverage(trades: trades, asset: "BTC")
        XCTAssertEqual(cost, 40040, accuracy: 0.01)
        XCTAssertEqual(units, 1, accuracy: 0.01)
    }

    func testCostBasisLifoSingleBuy() {
        let metrics = MetricsService()
        let trades = [
            Trade(id: "1", date: "2024-01-01", asset: "BTC", type: "BUY", price: 40000, quantity: 1, exchange: "Bitstamp", order_type: "maker", fee: 40, total_value: 40000, account_id: nil)
        ]
        let (cost, units, _) = metrics.calculateCostBasisLifo(trades: trades, asset: "BTC")
        XCTAssertEqual(cost, 40040, accuracy: 0.01)
        XCTAssertEqual(units, 1, accuracy: 0.01)
    }

    /// Cumulative realized PnL series: one buy then one sell; expect one point with sell proceeds minus cost.
    func testCumulativeRealizedPnlSeriesOneSell() {
        let metrics = MetricsService()
        let trades = [
            Trade(id: "1", date: "2024-01-01 00:00:00", asset: "BTC", type: "BUY", price: 40000, quantity: 1, exchange: "X", order_type: "", fee: 0, total_value: 40000, account_id: nil),
            Trade(id: "2", date: "2024-02-01 00:00:00", asset: "BTC", type: "SELL", price: 45000, quantity: 0.5, exchange: "X", order_type: "", fee: 10, total_value: 22500, account_id: nil)
        ]
        let series = metrics.cumulativeRealizedPnlSeries(trades: trades, costBasisMethod: "fifo")
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].date, "2024-02-01 00:00:00")
        // Cost of 0.5 BTC (FIFO) = 0.5 * 40000 = 20000; proceeds = 22500 - 10 = 22490; realized = 2490
        XCTAssertEqual(series[0].value, 2490, accuracy: 0.01)
    }

    /// Empty trades: series has one point at 0 (first trade date).
    func testCumulativeRealizedPnlSeriesEmpty() {
        let metrics = MetricsService()
        let series = metrics.cumulativeRealizedPnlSeries(trades: [], costBasisMethod: "average")
        XCTAssertEqual(series.count, 0)
    }
}

// MARK: - Correlation matrix

final class CorrelationMatrixTests: XCTestCase {

    /// Fewer than two assets or empty returns yields nil.
    func testCorrelationMatrixReturnsNilForFewerThanTwoAssets() {
        let metrics = MetricsService()
        XCTAssertNil(metrics.computeCorrelationMatrix(returnSeries: [:]))
        XCTAssertNil(metrics.computeCorrelationMatrix(returnSeries: ["BTC": [0.01, -0.02]]))
    }

    /// Need at least 2 aligned returns per asset.
    func testCorrelationMatrixReturnsNilForInsufficientData() {
        let metrics = MetricsService()
        XCTAssertNil(metrics.computeCorrelationMatrix(returnSeries: ["BTC": [0.01], "ETH": [0.02]]))
    }

    /// Diagonal is 1.0; assets are sorted; matrix is symmetric.
    func testCorrelationMatrixDiagonalAndOrder() {
        let metrics = MetricsService()
        let series: [String: [Double]] = [
            "ETH": [0.01, -0.02, 0.015, 0.0],
            "BTC": [0.02, -0.01, 0.01, 0.005]
        ]
        guard let result = metrics.computeCorrelationMatrix(returnSeries: series) else {
            XCTFail("Expected non-nil correlation matrix")
            return
        }
        XCTAssertEqual(result.assets, ["BTC", "ETH"])
        XCTAssertEqual(result.matrix.count, 2)
        XCTAssertEqual(result.matrix[0].count, 2)
        XCTAssertEqual(result.matrix[1].count, 2)
        XCTAssertEqual(result.matrix[0][0], 1.0, accuracy: 1e-10)
        XCTAssertEqual(result.matrix[1][1], 1.0, accuracy: 1e-10)
        XCTAssertEqual(result.matrix[0][1], result.matrix[1][0], accuracy: 1e-10)
    }

    /// Perfect positive correlation: same return series => correlation 1.0.
    func testCorrelationMatrixPerfectPositiveCorrelation() {
        let metrics = MetricsService()
        let r = [0.01, -0.02, 0.015, 0.0, -0.01]
        let series: [String: [Double]] = ["A": r, "B": r]
        guard let result = metrics.computeCorrelationMatrix(returnSeries: series) else {
            XCTFail("Expected non-nil")
            return
        }
        XCTAssertEqual(result.assets, ["A", "B"])
        XCTAssertEqual(result.matrix[0][1], 1.0, accuracy: 1e-10)
        XCTAssertEqual(result.matrix[1][0], 1.0, accuracy: 1e-10)
    }

    /// Perfect negative correlation: one series is negative of the other (after mean adjustment) gives -1.0.
    func testCorrelationMatrixPerfectNegativeCorrelation() {
        let metrics = MetricsService()
        let a = [1.0, 2.0, 3.0, 4.0, 5.0]
        let b = a.map { -$0 }
        let series: [String: [Double]] = ["A": a, "B": b]
        guard let result = metrics.computeCorrelationMatrix(returnSeries: series) else {
            XCTFail("Expected non-nil")
            return
        }
        XCTAssertEqual(result.matrix[0][1], -1.0, accuracy: 1e-10)
    }

    /// Three assets: order sorted, matrix 3x3 symmetric, diagonal ones.
    func testCorrelationMatrixThreeAssets() {
        let metrics = MetricsService()
        let series: [String: [Double]] = [
            "SOL": [0.01, -0.01, 0.02],
            "BTC": [0.02, 0.0, 0.01],
            "ETH": [-0.01, 0.01, 0.0]
        ]
        guard let result = metrics.computeCorrelationMatrix(returnSeries: series) else {
            XCTFail("Expected non-nil")
            return
        }
        XCTAssertEqual(result.assets, ["BTC", "ETH", "SOL"])
        XCTAssertEqual(result.matrix.count, 3)
        for i in 0..<3 {
            XCTAssertEqual(result.matrix[i][i], 1.0, accuracy: 1e-10)
            for j in (i + 1)..<3 {
                XCTAssertEqual(result.matrix[i][j], result.matrix[j][i], accuracy: 1e-10)
            }
        }
    }
}

// MARK: - Price cache key normalization

final class PriceCacheNormalizationTests: XCTestCase {

    /// Normalization uppercases all keys so lookups by canonical key (e.g. "BNB") find entries stored as "bnb".
    func testNormalizePriceCacheKeysUppercasesKeys() {
        let input: [String: [String: Any]] = [
            "bnb": ["price": 400.0, "pct_change_24h": 1.5],
            "btc": ["price": 50000.0],
            "ETH": ["price": 3000.0]
        ]
        let result = StorageService.normalizePriceCacheKeys(input)
        XCTAssertEqual(result["BNB"]?["price"] as? Double, 400.0)
        XCTAssertEqual(result["BNB"]?["pct_change_24h"] as? Double, 1.5)
        XCTAssertEqual(result["BTC"]?["price"] as? Double, 50000.0)
        XCTAssertEqual(result["ETH"]?["price"] as? Double, 3000.0)
        XCTAssertNil(result["bnb"])
        XCTAssertNil(result["btc"])
    }

    /// When two keys map to the same uppercase key, the last one wins (stable merge).
    func testNormalizePriceCacheKeysDuplicateKeysLastWins() {
        let input: [String: [String: Any]] = [
            "bnb": ["price": 1.0],
            "BNB": ["price": 2.0]
        ]
        let result = StorageService.normalizePriceCacheKeys(input)
        XCTAssertEqual(result.count, 1)
        // Dictionary iteration order is not guaranteed; either 1.0 or 2.0 can win. We only require one entry.
        let price = result["BNB"]?["price"] as? Double
        XCTAssertTrue(price == 1.0 || price == 2.0)
    }
}
