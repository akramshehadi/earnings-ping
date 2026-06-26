import AppKit
import Combine
import Network
import SwiftData

/// What kicked off a refresh. Informational; all triggers run the same pass.
enum RefreshTrigger: Equatable, Sendable {
    case launch, timer, wake, network, manual
}

/// Owns the refresh lifecycle: triggers (launch, ~6h timer, wake-from-sleep,
/// network-reconnect, manual), retry backoff, and the observable status the
/// menu surfaces. The actual upsert work lives in `RefreshEngine`.
@MainActor
final class RefreshCoordinator: ObservableObject {
    /// A refresh pass is in flight.
    @Published private(set) var isRefreshing = false
    /// When the watchlist was last fully refreshed with no failures.
    @Published private(set) var lastSuccessfulRefresh: Date?
    /// Every ticker failed on auth/missing-key — the user needs to add a key.
    @Published private(set) var needsAPIKey = false
    /// Short, user-facing summary of the most recent failure, if any.
    @Published private(set) var lastErrorSummary: String?

    /// Date Changes detected during refresh, published for any observer (e.g. a
    /// future calendar view). Immediate "moved" alerts are driven directly from
    /// each pass's outcome via `notifications`, below.
    let dateChanges = PassthroughSubject<DateChange, Never>()

    private let engine: RefreshEngine
    private let modelContainer: ModelContainer
    private let notifications: EarningsNotificationScheduler?
    private let normalInterval: Duration
    private let now: () -> Date

    private var consecutiveTransientFailures = 0
    private var scheduledTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var lastPathSatisfied = true
    private var wakeObserver: NSObjectProtocol?
    private var didStart = false

    init(
        provider: any EarningsProvider,
        modelContainer: ModelContainer,
        notifications: EarningsNotificationScheduler? = nil,
        interval: Duration = .seconds(6 * 3600),
        windowDays: Int = 90,
        now: @escaping () -> Date = Date.init
    ) {
        self.engine = RefreshEngine(provider: provider, windowDays: windowDays, now: now)
        self.modelContainer = modelContainer
        self.notifications = notifications
        self.normalInterval = interval
        self.now = now
    }

    deinit {
        scheduledTask?.cancel()
        pathMonitor?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    // MARK: Lifecycle

    /// Begin observing triggers and run the launch refresh. Idempotent.
    func start() {
        guard !didStart else { return }
        didStart = true
        observeWake()
        observeNetwork()
        Task {
            await notifications?.requestAuthorizationIfNeeded()
            await refresh(trigger: .launch)
        }
    }

    /// Manual "Refresh now".
    func refreshNow() {
        Task { await refresh(trigger: .manual) }
    }

    // MARK: Refresh

    private func refresh(trigger: RefreshTrigger) async {
        guard !isRefreshing else { return }   // coalesce overlapping triggers
        isRefreshing = true
        defer { isRefreshing = false }

        let outcome = await engine.refresh(in: modelContainer.mainContext)
        for change in outcome.dateChanges {
            dateChanges.send(change)
        }
        await driveNotifications(for: outcome)
        applyStatus(outcome)
        scheduleNext(for: outcome)
    }

    /// Fire one immediate alert per Date Change, then re-sync scheduled reminders
    /// from the just-refreshed store (this is also what reschedules a moved date).
    private func driveNotifications(for outcome: RefreshOutcome) async {
        guard let notifications else { return }
        for change in outcome.dateChanges {
            await notifications.handleDateChange(change)
        }
        await notifications.syncReminders(for: reminderTargets())
    }

    /// Snapshot the current watchlist's upcoming events as plain reminder values.
    private func reminderTargets() -> [ReminderTarget] {
        let tickers = (try? modelContainer.mainContext.fetch(FetchDescriptor<Ticker>())) ?? []
        return tickers.compactMap { ticker in
            guard let event = ticker.event else { return nil }
            return ReminderTarget(
                symbol: ticker.symbol,
                companyName: ticker.companyName,
                eventDate: event.date,
                session: event.session
            )
        }
    }

    private func applyStatus(_ outcome: RefreshOutcome) {
        if outcome.hadFailures {
            needsAPIKey = outcome.allFailedOnAuth
            lastErrorSummary = summarize(outcome.failures)
            if !outcome.allFailedOnAuth {
                // partial/transient: keep last-known data, mark stale-ish via summary
                if outcome.updated == 0 && outcome.unchanged == 0 {
                    // total transient failure — leave lastSuccessfulRefresh alone
                } else {
                    lastSuccessfulRefresh = outcome.finishedAt
                }
            }
        } else {
            needsAPIKey = false
            lastErrorSummary = nil
            lastSuccessfulRefresh = outcome.finishedAt
        }
    }

    private func scheduleNext(for outcome: RefreshOutcome) {
        let interval: Duration
        if outcome.hadFailures && !outcome.allFailedOnAuth {
            consecutiveTransientFailures += 1
            interval = RefreshBackoff.interval(failureCount: consecutiveTransientFailures)
        } else {
            // success, or auth-only failure (no point retrying fast without a key)
            consecutiveTransientFailures = 0
            interval = normalInterval
        }
        scheduleNext(after: interval)
    }

    private func scheduleNext(after interval: Duration) {
        scheduledTask?.cancel()
        scheduledTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await self?.refresh(trigger: .timer)
        }
    }

    private func summarize(_ failures: [SymbolFailure]) -> String? {
        guard !failures.isEmpty else { return nil }
        let allAuth = failures.allSatisfy { $0.error == .unauthorized || $0.error == .missingAPIKey }
        if allAuth {
            return "Add your Finnhub key to fetch dates."
        }
        let n = failures.count
        return "Couldn't update \(n) ticker\(n == 1 ? "" : "s") — retrying."
    }

    // MARK: Triggers

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh(trigger: .wake) }
        }
    }

    private func observeNetwork() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.handlePath(satisfied: satisfied) }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        pathMonitor = monitor
    }

    /// Refresh on a connectivity *recovery* (unsatisfied → satisfied) only.
    private func handlePath(satisfied: Bool) {
        defer { lastPathSatisfied = satisfied }
        guard satisfied, !lastPathSatisfied else { return }
        Task { await refresh(trigger: .network) }
    }
}
