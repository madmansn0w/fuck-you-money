import XCTest
@testable import CryptoTrackerCore

/// Tests for AssetMarketData computed properties (e.g. volumeToMarketCap).
final class AssetMarketDataTests: XCTestCase {

    /// volumeToMarketCap is nil when marketCap is nil.
    func testVolumeToMarketCapNilWhenMarketCapNil() {
        let d = AssetMarketData(
            price: 50_000,
            priceChange24h: nil,
            priceChangePct24h: nil,
            volume24h: 1_000_000,
            marketCap: nil,
            fullyDilutedValuation: nil,
            circulatingSupply: nil,
            pct7d: nil,
            pct14d: nil,
            pct30d: nil,
            pct60d: nil,
            pct200d: nil,
            pct1y: nil,
            name: nil,
            assetDescription: nil,
            homepage: nil,
            sentimentVotesUpPct: nil,
            sentimentVotesDownPct: nil
        )
        XCTAssertNil(d.volumeToMarketCap)
    }

    /// volumeToMarketCap is nil when volume24h is nil.
    func testVolumeToMarketCapNilWhenVolumeNil() {
        let d = AssetMarketData(
            price: 50_000,
            priceChange24h: nil,
            priceChangePct24h: nil,
            volume24h: nil,
            marketCap: 1_000_000_000,
            fullyDilutedValuation: nil,
            circulatingSupply: nil,
            pct7d: nil,
            pct14d: nil,
            pct30d: nil,
            pct60d: nil,
            pct200d: nil,
            pct1y: nil,
            name: nil,
            assetDescription: nil,
            homepage: nil,
            sentimentVotesUpPct: nil,
            sentimentVotesDownPct: nil
        )
        XCTAssertNil(d.volumeToMarketCap)
    }

    /// volumeToMarketCap is nil when marketCap is zero.
    func testVolumeToMarketCapNilWhenMarketCapZero() {
        let d = AssetMarketData(
            price: 1,
            priceChange24h: nil,
            priceChangePct24h: nil,
            volume24h: 100,
            marketCap: 0,
            fullyDilutedValuation: nil,
            circulatingSupply: nil,
            pct7d: nil,
            pct14d: nil,
            pct30d: nil,
            pct60d: nil,
            pct200d: nil,
            pct1y: nil,
            name: nil,
            assetDescription: nil,
            homepage: nil,
            sentimentVotesUpPct: nil,
            sentimentVotesDownPct: nil
        )
        XCTAssertNil(d.volumeToMarketCap)
    }

    /// volumeToMarketCap returns volume / marketCap when both set.
    func testVolumeToMarketCapWhenBothSet() {
        let d = AssetMarketData(
            price: 50_000,
            priceChange24h: nil,
            priceChangePct24h: nil,
            volume24h: 50_000_000,
            marketCap: 1_000_000_000,
            fullyDilutedValuation: nil,
            circulatingSupply: nil,
            pct7d: nil,
            pct14d: nil,
            pct30d: nil,
            pct60d: nil,
            pct200d: nil,
            pct1y: nil,
            name: nil,
            assetDescription: nil,
            homepage: nil,
            sentimentVotesUpPct: nil,
            sentimentVotesDownPct: nil
        )
        XCTAssertNotNil(d.volumeToMarketCap)
        XCTAssertEqual(d.volumeToMarketCap!, 0.05, accuracy: 1e-10)
    }
}
