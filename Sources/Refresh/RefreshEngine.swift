import Foundation
import SwiftData

/// One ticker that failed to refresh this pass, with the typed reason.
struct SymbolFailure: Equatable, Sendable {
    let symbol: String
    let error: EarningsProviderError
}

/// Result of a single refresh pass over the whole watchlist.
struct RefreshOutcome: Equatable, Sendable {
    var startedAt: Date
    var finishedAt: Date = .distantPast
    var updated = 0
    var unchanged = 0
    var cleared = 0
    var dateChanges: [DateChange] = []
    var failures: [SymbolFailure] = []

    var hadFailures: Bool { !failures.isEmpty }

    private var isAuth: (SymbolFailure) -> Bool {
        { $0.error == .unauthorized || $0.error == .missingAPIKey }
    }

    /// True when every ticker failed and they all failed on auth/missing-key —
    /// i.e. there's nothing to retry until the user supplies a valid key.
    var allFailedOnAuth: Bool {
        !failures.isEmpty && updated == 0 && unchanged == 0 && cleared == 0
            && failures.allSatisfy(isAuth)
    }
}

/// Refreshes stored `EarningsEvent`s from the provider, one ticker at a time,
/// and reports what changed. Runs on the main actor against the SwiftData
/// `mainContext`, so `@Query` views update automatically and there's no
/// cross-context Sendable handling — fine for a watchlist capped at ~100.
@MainActor
struct RefreshEngine {
    private let provider: any EarningsProvider
    private let windowDays: Int
    private let now: () -> Date

    init(
        provider: any EarningsProvider,
        windowDays: Int = 90,
        now: @escaping () -> Date = Date.init
    ) {
        self.provider = provider
        self.windowDays = windowDays
        self.now = now
    }

    func refresh(in context: ModelContext) async -> RefreshOutcome {
        let started = now()
        var outcome = RefreshOutcome(startedAt: started)

        let tickers: [Ticker]
        do {
            tickers = try context.fetch(FetchDescriptor<Ticker>())
        } catch {
            outcome.finishedAt = now()
            return outcome
        }

        let window = DateInterval(start: started, duration: TimeInterval(windowDays * 86_400))

        for ticker in tickers {
            do {
                let incoming = try await provider.nextUpcomingEarnings(symbol: ticker.symbol, within: window)
                apply(incoming, to: ticker, asOf: started, into: &outcome, in: context)
            } catch let error as EarningsProviderError {
                outcome.failures.append(SymbolFailure(symbol: ticker.symbol, error: error))
            } catch {
                outcome.failures.append(SymbolFailure(symbol: ticker.symbol, error: .network(error.localizedDescription)))
            }
        }

        // Keep last-known data on save failure; the pass is still reported.
        try? context.save()
        outcome.finishedAt = now()
        return outcome
    }

    /// Upsert one ticker's event from its fetched value (or absence).
    private func apply(
        _ incoming: UpcomingEarnings?,
        to ticker: Ticker,
        asOf now: Date,
        into outcome: inout RefreshOutcome,
        in context: ModelContext
    ) {
        guard let incoming else {
            // Successful fetch with no upcoming event: only drop a stored event
            // once its date has passed (a future event would still be returned).
            if let event = ticker.event, event.date < now {
                context.delete(event)
                ticker.event = nil
                outcome.cleared += 1
            }
            return
        }

        switch RefreshReconciler.reconcile(existingDate: ticker.event?.date, incomingDate: incoming.date) {
        case .created:
            ticker.event = EarningsEvent(
                date: incoming.date,
                session: incoming.session,
                fiscalPeriod: incoming.fiscalPeriod,
                epsEstimate: incoming.epsEstimate,
                lastFetchedAt: incoming.fetchedAt
            )
            outcome.updated += 1

        case .unchanged:
            if let event = ticker.event {
                updateDisplayFields(event, from: incoming)
            }
            outcome.unchanged += 1

        case .dateChanged(let from, let to):
            if let event = ticker.event {
                event.previousDate = from
                event.date = to
                updateDisplayFields(event, from: incoming)
            }
            outcome.dateChanges.append(
                DateChange(
                    symbol: ticker.symbol,
                    companyName: ticker.companyName,
                    previousDate: from,
                    newDate: to,
                    newSession: incoming.session
                )
            )
            outcome.updated += 1
        }
    }

    private func updateDisplayFields(_ event: EarningsEvent, from incoming: UpcomingEarnings) {
        event.session = incoming.session
        event.fiscalPeriod = incoming.fiscalPeriod
        event.epsEstimate = incoming.epsEstimate
        event.lastFetchedAt = incoming.fetchedAt
    }
}
