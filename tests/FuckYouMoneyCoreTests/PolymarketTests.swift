import XCTest
@testable import FuckYouMoneyCore

/// Tests for Polymarket Core: PolymarketMarket.arbGap, OrderBookSnapshot spread/midpoint,
/// and Gamma/CLOB JSON decoding.
final class PolymarketTests: XCTestCase {

    // MARK: - PolymarketMarket.arbGap

    /// arbGap is nil when outcomes are not exactly ["Yes", "No"].
    func testArbGapNilWhenNotYesNo() {
        let m = PolymarketMarket(
            id: "1",
            question: "Q",
            outcomes: ["A", "B"],
            outcomePrices: [0.4, 0.5],
            endDate: nil,
            slug: "s",
            conditionId: nil,
            bestBid: nil,
            bestAsk: nil,
            spread: nil,
            clobTokenIds: []
        )
        XCTAssertNil(m.arbGap)
    }

    /// arbGap is nil when outcome count is not 2.
    func testArbGapNilWhenThreeOutcomes() {
        let m = PolymarketMarket(
            id: "1",
            question: "Q",
            outcomes: ["Yes", "No", "Other"],
            outcomePrices: [0.3, 0.3, 0.3],
            endDate: nil,
            slug: "s",
            conditionId: nil,
            bestBid: nil,
            bestAsk: nil,
            spread: nil,
            clobTokenIds: []
        )
        XCTAssertNil(m.arbGap)
    }

    /// arbGap is nil when YES + NO >= 1 (no opportunity).
    func testArbGapNilWhenSumAtLeastOne() {
        let m = PolymarketMarket(
            id: "1",
            question: "Q",
            outcomes: ["Yes", "No"],
            outcomePrices: [0.5, 0.5],
            endDate: nil,
            slug: "s",
            conditionId: nil,
            bestBid: nil,
            bestAsk: nil,
            spread: nil,
            clobTokenIds: []
        )
        XCTAssertNil(m.arbGap)
    }

    /// arbGap returns positive value when YES + NO < 1.
    func testArbGapPositiveWhenSumBelowOne() {
        let m = PolymarketMarket(
            id: "1",
            question: "Q",
            outcomes: ["Yes", "No"],
            outcomePrices: [0.48, 0.48],
            endDate: nil,
            slug: "s",
            conditionId: nil,
            bestBid: nil,
            bestAsk: nil,
            spread: nil,
            clobTokenIds: []
        )
        XCTAssertEqual(m.arbGap ?? -1, 0.04, accuracy: 0.0001)
    }

    /// arbGap uses correct Yes/No indices when order differs (No first, Yes second).
    func testArbGapNoYesOrder() {
        let m = PolymarketMarket(
            id: "1",
            question: "Q",
            outcomes: ["No", "Yes"],
            outcomePrices: [0.45, 0.50],
            endDate: nil,
            slug: "s",
            conditionId: nil,
            bestBid: nil,
            bestAsk: nil,
            spread: nil,
            clobTokenIds: []
        )
        XCTAssertEqual(m.arbGap ?? -1, 0.05, accuracy: 0.0001)
        let m2 = PolymarketMarket(
            id: "2",
            question: "Q2",
            outcomes: ["No", "Yes"],
            outcomePrices: [0.40, 0.50],
            endDate: nil,
            slug: "s2",
            conditionId: nil,
            bestBid: nil,
            bestAsk: nil,
            spread: nil,
            clobTokenIds: []
        )
        XCTAssertEqual(m2.arbGap ?? -1, 0.10, accuracy: 0.0001)
    }

    // MARK: - OrderBookSnapshot

    /// bestBid is first bid price; bestAsk is first ask price (book is assumed sorted).
    func testOrderBookBestBidAsk() {
        let book = OrderBookSnapshot(
            tokenId: "t1",
            bids: [(0.49, 100), (0.48, 200)],
            asks: [(0.52, 50), (0.53, 100)],
            tickSize: nil,
            minOrderSize: nil
        )
        XCTAssertEqual(book.bestBid, 0.49)
        XCTAssertEqual(book.bestAsk, 0.52)
    }

    /// spread is bestAsk - bestBid when both present.
    func testOrderBookSpread() {
        let book = OrderBookSnapshot(
            tokenId: "t1",
            bids: [(0.48, 100)],
            asks: [(0.52, 100)],
            tickSize: nil,
            minOrderSize: nil
        )
        XCTAssertEqual(book.spread ?? -1, 0.04, accuracy: 0.0001)
    }

    /// midpoint is average of best bid and ask.
    func testOrderBookMidpoint() {
        let book = OrderBookSnapshot(
            tokenId: "t1",
            bids: [(0.48, 100)],
            asks: [(0.52, 100)],
            tickSize: nil,
            minOrderSize: nil
        )
        XCTAssertEqual(book.midpoint ?? -1, 0.50, accuracy: 0.0001)
    }

    /// spread and midpoint are nil when bids or asks empty.
    func testOrderBookSpreadMidpointNilWhenEmptySide() {
        let noBids = OrderBookSnapshot(tokenId: "t", bids: [], asks: [(0.50, 10)], tickSize: nil, minOrderSize: nil)
        XCTAssertNil(noBids.spread)
        XCTAssertNil(noBids.midpoint)
        let noAsks = OrderBookSnapshot(tokenId: "t", bids: [(0.50, 10)], asks: [], tickSize: nil, minOrderSize: nil)
        XCTAssertNil(noAsks.spread)
        XCTAssertNil(noAsks.midpoint)
    }

    // MARK: - decodeOrderBook

    /// decodeOrderBook parses bids/asks with string or number price/size.
    func testDecodeOrderBook() {
        let json = """
        {"bids":[{"price":"0.48","size":"100"},{"price":0.47,"size":200}],"asks":[{"price":"0.52","size":"50"}]}
        """
        let data = json.data(using: .utf8)!
        guard let book = PolymarketService.decodeOrderBook(tokenId: "tid", from: data) else {
            XCTFail("decodeOrderBook returned nil")
            return
        }
        XCTAssertEqual(book.tokenId, "tid")
        XCTAssertEqual(book.bids.count, 2)
        XCTAssertEqual(book.bids[0].price, 0.48, accuracy: 0.0001)
        XCTAssertEqual(book.bids[0].size, 100, accuracy: 0.0001)
        XCTAssertEqual(book.bids[1].price, 0.47, accuracy: 0.0001)
        XCTAssertEqual(book.asks.count, 1)
        XCTAssertEqual(book.asks[0].price, 0.52, accuracy: 0.0001)
        XCTAssertEqual(book.spread ?? -1, 0.04, accuracy: 0.0001)
    }

    /// decodeOrderBook returns nil for invalid JSON.
    func testDecodeOrderBookInvalidJSON() {
        let data = "not json".data(using: .utf8)!
        XCTAssertNil(PolymarketService.decodeOrderBook(tokenId: "t", from: data))
    }

    // MARK: - decodeEvents

    /// decodeEvents parses minimal event with markets array.
    func testDecodeEventsMinimal() {
        let json = """
        [{"id":"e1","slug":"slug1","title":"Title","markets":[{"id":"m1","question":"Q?","slug":"m1","outcomes":"[\\"Yes\\",\\"No\\"]","outcomePrices":"[\\"0.5\\",\\"0.5\\"]"}]}]
        """
        let data = json.data(using: .utf8)!
        let events = PolymarketService.decodeEvents(from: data)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].id, "e1")
        XCTAssertEqual(events[0].slug, "slug1")
        XCTAssertEqual(events[0].title, "Title")
        XCTAssertEqual(events[0].markets.count, 1)
        XCTAssertEqual(events[0].markets[0].id, "m1")
        XCTAssertEqual(events[0].markets[0].question, "Q?")
        XCTAssertEqual(events[0].markets[0].outcomes, ["Yes", "No"])
        XCTAssertEqual(events[0].markets[0].outcomePrices.count, 2)
    }

    /// decodeEvents returns empty for invalid JSON.
    func testDecodeEventsInvalidJSON() {
        let data = "[]".data(using: .utf8)!
        let events = PolymarketService.decodeEvents(from: data)
        XCTAssertEqual(events.count, 0)
        let bad = "not array".data(using: .utf8)!
        XCTAssertTrue(PolymarketService.decodeEvents(from: bad).isEmpty)
    }
}
