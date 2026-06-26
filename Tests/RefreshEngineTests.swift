import Foundation
import SwiftData
import Testing
@testable import EarningsPing

// MARK: - Scripted provider

/// A provider whose responses are scripted per symbol, one step consumed per
/// refresh pass. Lets a test drive "first pass returns X, second pass returns Y
/// (or throws)" to exercise Date Change and failure handling.
private final class ScriptedProvider: EarningsProvider, @unchecked Sendable {
    enum Step {
        case events([UpcomingEarnings])
        case fail(EarningsProviderError)
    }

    private let lock = NSLock()
    private var steps: [String: [Step]]

    init(_ steps: [String: [Step]]) { self.steps = steps }

    func searchSymbols(matching query: String) async throws -> [SymbolMatch] { [] }

    func fetchEarnings(symbol: String, within window: DateInterval) async throws -> [UpcomingEarnings] {
        let step: Step? = lock.withLock {
            let key = symbol.uppercased()
            guard var queue = steps[key], !queue.isEmpty else { return nil }
            let next = queue.removeFirst()
            steps[key] = queue
            return next
        }
        switch step {
        case .events(let e): return e
        case .fail(let error): throw error
        case .none: return []
        }
    }
}

// MARK: - Helpers

@MainActor
private func makeContext() -> ModelContext {
    ModelContext(AppModelContainer.makeInMemory())
}

private let fixedNow = FinnhubProvider.dayFormatter.date(from: "2026-06-25")!

private func earnings(_ symbol: String, _ ymd: String, _ session: Session = .amc) -> UpcomingEarnings {
    UpcomingEarnings(
        symbol: symbol,
        date: FinnhubProvider.dayFormatter.date(from: ymd)!,
        session: session,
        fiscalPeriod: "Q3 FY2026",
        epsEstimate: 1.93,
        fetchedAt: fixedNow
    )
}

@MainActor
private func makeEngine(_ provider: ScriptedProvider) -> RefreshEngine {
    RefreshEngine(provider: provider, windowDays: 90, now: { fixedNow })
}

// MARK: - Reconciliation (pure)

@Suite("Refresh reconciliation")
struct RefreshReconciliationTests {
    private let day1 = FinnhubProvider.dayFormatter.date(from: "2026-07-29")!
    private let day2 = FinnhubProvider.dayFormatter.date(from: "2026-07-22")!

    @Test func noExistingDateIsCreated() {
        #expect(RefreshReconciler.reconcile(existingDate: nil, incomingDate: day1) == .created)
    }

    @Test func sameDayIsUnchanged() {
        #expect(RefreshReconciler.reconcile(existingDate: day1, incomingDate: day1) == .unchanged)
    }

    @Test func differentDayIsDateChange() {
        #expect(RefreshReconciler.reconcile(existingDate: day1, incomingDate: day2) == .dateChanged(from: day1, to: day2))
    }
}

// MARK: - Backoff (pure)

@Suite("Refresh backoff")
struct RefreshBackoffTests {
    @Test func growsExponentially() {
        #expect(RefreshBackoff.interval(failureCount: 1) == .seconds(30))
        #expect(RefreshBackoff.interval(failureCount: 2) == .seconds(60))
        #expect(RefreshBackoff.interval(failureCount: 3) == .seconds(120))
    }

    @Test func capsAtThirtyMinutes() {
        #expect(RefreshBackoff.interval(failureCount: 99) == .seconds(30 * 60))
    }
}

// MARK: - Engine

@MainActor
@Suite("Refresh engine")
struct RefreshEngineTests {
    @Test func createsEventOnFirstFetch() async throws {
        let context = makeContext()
        context.insert(Ticker(symbol: "AAPL", companyName: "Apple Inc"))
        let engine = makeEngine(ScriptedProvider(["AAPL": [.events([earnings("AAPL", "2026-07-29")])]]))

        let outcome = await engine.refresh(in: context)

        #expect(outcome.updated == 1)
        #expect(outcome.dateChanges.isEmpty)
        let event = try #require(context.fetch(FetchDescriptor<Ticker>()).first?.event)
        #expect(event.session == .amc)
        #expect(event.previousDate == nil)
    }

    @Test func sameDateSecondPassIsUnchanged() async throws {
        let context = makeContext()
        context.insert(Ticker(symbol: "AAPL", companyName: "Apple Inc"))
        let provider = ScriptedProvider([
            "AAPL": [
                .events([earnings("AAPL", "2026-07-29", .amc)]),
                .events([earnings("AAPL", "2026-07-29", .bmo)]),   // same day, new session
            ]
        ])
        let engine = makeEngine(provider)

        _ = await engine.refresh(in: context)
        let outcome = await engine.refresh(in: context)

        #expect(outcome.unchanged == 1)
        #expect(outcome.dateChanges.isEmpty)
        let event = try #require(context.fetch(FetchDescriptor<Ticker>()).first?.event)
        #expect(event.session == .bmo)            // display field updated
        #expect(event.previousDate == nil)        // but not treated as a move
    }

    @Test func movedDateRecordsAndEmitsDateChange() async throws {
        let context = makeContext()
        context.insert(Ticker(symbol: "AAPL", companyName: "Apple Inc"))
        let provider = ScriptedProvider([
            "AAPL": [
                .events([earnings("AAPL", "2026-07-29")]),
                .events([earnings("AAPL", "2026-07-22")]),   // moved up a week
            ]
        ])
        let engine = makeEngine(provider)

        _ = await engine.refresh(in: context)
        let outcome = await engine.refresh(in: context)

        #expect(outcome.dateChanges.count == 1)
        let change = try #require(outcome.dateChanges.first)
        #expect(change.symbol == "AAPL")
        #expect(change.previousDate == FinnhubProvider.dayFormatter.date(from: "2026-07-29"))
        #expect(change.newDate == FinnhubProvider.dayFormatter.date(from: "2026-07-22"))

        let event = try #require(context.fetch(FetchDescriptor<Ticker>()).first?.event)
        #expect(event.date == FinnhubProvider.dayFormatter.date(from: "2026-07-22"))
        #expect(event.previousDate == FinnhubProvider.dayFormatter.date(from: "2026-07-29"))
    }

    @Test func transientFailurePreservesLastKnownData() async throws {
        let context = makeContext()
        context.insert(Ticker(symbol: "AAPL", companyName: "Apple Inc"))
        let provider = ScriptedProvider([
            "AAPL": [
                .events([earnings("AAPL", "2026-07-29")]),
                .fail(.rateLimited),
            ]
        ])
        let engine = makeEngine(provider)

        _ = await engine.refresh(in: context)
        let outcome = await engine.refresh(in: context)

        #expect(outcome.failures == [SymbolFailure(symbol: "AAPL", error: .rateLimited)])
        #expect(outcome.allFailedOnAuth == false)
        // Prior event survives the failed pass.
        let event = try #require(context.fetch(FetchDescriptor<Ticker>()).first?.event)
        #expect(event.date == FinnhubProvider.dayFormatter.date(from: "2026-07-29"))
    }

    @Test func missingKeyFailureFlagsAuth() async throws {
        let context = makeContext()
        context.insert(Ticker(symbol: "AAPL", companyName: "Apple Inc"))
        let engine = makeEngine(ScriptedProvider(["AAPL": [.fail(.missingAPIKey)]]))

        let outcome = await engine.refresh(in: context)

        #expect(outcome.allFailedOnAuth)
        #expect(try context.fetch(FetchDescriptor<Ticker>()).first?.event == nil)
    }

    @Test func clearsEventThatHasPassedWhenNoneUpcoming() async throws {
        let context = makeContext()
        let ticker = Ticker(symbol: "AAPL", companyName: "Apple Inc")
        context.insert(ticker)
        // A stored event already in the past relative to fixedNow.
        ticker.event = EarningsEvent(date: FinnhubProvider.dayFormatter.date(from: "2026-06-01")!, session: .amc)
        try context.save()

        let engine = makeEngine(ScriptedProvider(["AAPL": [.events([])]]))
        let outcome = await engine.refresh(in: context)

        #expect(outcome.cleared == 1)
        #expect(try context.fetch(FetchDescriptor<Ticker>()).first?.event == nil)
        #expect(try context.fetch(FetchDescriptor<EarningsEvent>()).isEmpty)
    }
}
