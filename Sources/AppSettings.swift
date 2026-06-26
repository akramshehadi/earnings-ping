import Combine
import Foundation

/// User preferences, persisted in `UserDefaults`.
///
/// The settings surface (lead time, refresh cadence, imminent-window threshold,
/// max watchlist size, sort order) is edited in `SettingsView` (issue 07); the
/// API key and launch-at-login live outside `UserDefaults` (Keychain and
/// `SMAppService`). New preferences are added here as `@Published` properties
/// backed by `UserDefaults`.
@MainActor
final class AppSettings: ObservableObject {
    /// Hard upper bound on the watchlist size, regardless of preference.
    static let maxWatchlistCeiling = 100

    /// Maximum number of Tickers allowed on the Watchlist. Default 50, clamped
    /// to `1...maxWatchlistCeiling`. Surfaced in the settings UI in issue 07.
    @Published var maxWatchlistSize: Int {
        didSet {
            let clamped = min(max(maxWatchlistSize, 1), Self.maxWatchlistCeiling)
            if clamped != maxWatchlistSize {
                maxWatchlistSize = clamped
                return
            }
            defaults.set(maxWatchlistSize, forKey: Keys.maxWatchlistSize)
        }
    }

    /// Current Watchlist sort order. Default soonest-upcoming first.
    @Published var watchlistSortOrder: WatchlistSortOrder {
        didSet { defaults.set(watchlistSortOrder.rawValue, forKey: Keys.watchlistSortOrder) }
    }

    /// Highest allowed Imminent Window threshold, in calendar days.
    static let maxImminentWindowDays = 14

    /// How many calendar days ahead (NY-anchored) an upcoming Earnings Event
    /// starts badging the menu-bar icon (CONTEXT: *Imminent Window*) — a
    /// glanceable signal distinct from the trading-day *Lead Time* below.
    /// Default 3, clamped to `1...maxImminentWindowDays`. The settings control
    /// arrives in issue 07; the menu-bar badge reads this value today.
    @Published var imminentWindowDays: Int {
        didSet {
            let clamped = min(max(imminentWindowDays, 1), Self.maxImminentWindowDays)
            if clamped != imminentWindowDays {
                imminentWindowDays = clamped
                return
            }
            defaults.set(imminentWindowDays, forKey: Keys.imminentWindowDays)
        }
    }

    /// Bounds on the background refresh cadence, in hours.
    static let minRefreshIntervalHours = 1
    static let maxRefreshIntervalHours = 24

    /// How often (hours) the refresh engine re-fetches earnings dates on its
    /// normal timer. Default 6, clamped to
    /// `minRefreshIntervalHours...maxRefreshIntervalHours`. Read by
    /// `RefreshCoordinator` when scheduling the next pass, so a change takes
    /// effect from the following cycle without a restart.
    @Published var refreshIntervalHours: Int {
        didSet {
            let clamped = min(max(refreshIntervalHours, Self.minRefreshIntervalHours), Self.maxRefreshIntervalHours)
            if clamped != refreshIntervalHours {
                refreshIntervalHours = clamped
                return
            }
            defaults.set(refreshIntervalHours, forKey: Keys.refreshIntervalHours)
        }
    }

    /// Highest allowed reminder lead time, in trading days.
    static let maxLeadTimeTradingDays = 10

    /// How many trading days before an Earnings Event the morning reminder
    /// fires (CONTEXT: *Lead Time*). Default 1, clamped to
    /// `0...maxLeadTimeTradingDays`. The settings control arrives in issue 07;
    /// the notification scheduler reads this value today.
    @Published var leadTimeTradingDays: Int {
        didSet {
            let clamped = min(max(leadTimeTradingDays, 0), Self.maxLeadTimeTradingDays)
            if clamped != leadTimeTradingDays {
                leadTimeTradingDays = clamped
                return
            }
            defaults.set(leadTimeTradingDays, forKey: Keys.leadTimeTradingDays)
        }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let maxWatchlistSize = "maxWatchlistSize"
        static let watchlistSortOrder = "watchlistSortOrder"
        static let leadTimeTradingDays = "leadTimeTradingDays"
        static let imminentWindowDays = "imminentWindowDays"
        static let refreshIntervalHours = "refreshIntervalHours"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.maxWatchlistSize = (defaults.object(forKey: Keys.maxWatchlistSize) as? Int) ?? 50
        self.watchlistSortOrder = defaults.string(forKey: Keys.watchlistSortOrder)
            .flatMap(WatchlistSortOrder.init(rawValue:)) ?? .soonestFirst
        self.leadTimeTradingDays = (defaults.object(forKey: Keys.leadTimeTradingDays) as? Int) ?? 1
        self.imminentWindowDays = (defaults.object(forKey: Keys.imminentWindowDays) as? Int) ?? 3
        self.refreshIntervalHours = (defaults.object(forKey: Keys.refreshIntervalHours) as? Int) ?? 6
    }
}
