import Foundation
import SwiftData
import Testing
@testable import EarningsPing

@Suite("Watchlist add-validation")
struct WatchlistValidationTests {
    @Test func allowsNewSymbol() {
        let outcome = WatchlistOperations.validateAdd(
            symbol: "AAPL", existingSymbols: ["MSFT"], maxSize: 50
        )
        #expect(outcome == .ok)
    }

    @Test func rejectsDuplicateCaseInsensitively() {
        let outcome = WatchlistOperations.validateAdd(
            symbol: "aapl", existingSymbols: ["AAPL"], maxSize: 50
        )
        #expect(outcome == .duplicate("AAPL"))
    }

    @Test func rejectsWhenAtCapacity() {
        let outcome = WatchlistOperations.validateAdd(
            symbol: "NVDA", existingSymbols: ["AAPL", "MSFT"], maxSize: 2
        )
        #expect(outcome == .full(2))
    }
}

@Suite("Watchlist sorting")
struct WatchlistSortingTests {
    @Test func alphabeticalBySymbol() {
        let tickers = [
            Ticker(symbol: "MSFT", companyName: "Microsoft"),
            Ticker(symbol: "AAPL", companyName: "Apple"),
        ]
        let sorted = WatchlistOperations.sorted(tickers, by: .alphabetical)
        #expect(sorted.map(\.symbol) == ["AAPL", "MSFT"])
    }

    @Test func soonestFirstPutsTickersWithoutEventLast() {
        let withEvent = Ticker(symbol: "ZZZ", companyName: "Z Corp")
        withEvent.event = EarningsEvent(date: Date(timeIntervalSince1970: 1_000_000))
        let withoutEvent = Ticker(symbol: "AAA", companyName: "A Corp")

        let sorted = WatchlistOperations.sorted([withoutEvent, withEvent], by: .soonestFirst)
        #expect(sorted.map(\.symbol) == ["ZZZ", "AAA"])
    }

    @Test func soonestFirstOrdersByEventDate() {
        let later = Ticker(symbol: "LAST", companyName: "Later")
        later.event = EarningsEvent(date: Date(timeIntervalSince1970: 2_000_000))
        let sooner = Ticker(symbol: "FRST", companyName: "Sooner")
        sooner.event = EarningsEvent(date: Date(timeIntervalSince1970: 1_000_000))

        let sorted = WatchlistOperations.sorted([later, sooner], by: .soonestFirst)
        #expect(sorted.map(\.symbol) == ["FRST", "LAST"])
    }
}

@Suite("SwiftData store")
struct PersistenceTests {
    @Test func insertAndFetchRoundTrips() throws {
        let context = ModelContext(AppModelContainer.makeInMemory())
        context.insert(Ticker(symbol: "AAPL", companyName: "Apple Inc"))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Ticker>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.symbol == "AAPL")
        #expect(fetched.first?.event == nil)
    }

    @Test func deletingTickerCascadesToItsEvent() throws {
        let context = ModelContext(AppModelContainer.makeInMemory())
        let ticker = Ticker(symbol: "AAPL", companyName: "Apple Inc")
        context.insert(ticker)
        ticker.event = EarningsEvent(date: .now, session: .bmo)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<EarningsEvent>()).count == 1)

        context.delete(ticker)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<EarningsEvent>()).isEmpty)
    }
}
