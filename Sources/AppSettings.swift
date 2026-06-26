import Combine
import Foundation

/// User preferences, persisted in `UserDefaults`.
///
/// Issue 01 only needs the Dock-icon toggle. The full settings surface (lead
/// time, refresh cadence, imminent-window threshold, launch-at-login, etc.)
/// arrives in issue 07; new preferences are added here as `@Published`
/// properties backed by `UserDefaults`.
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

    private let defaults: UserDefaults

    private enum Keys {
        static let maxWatchlistSize = "maxWatchlistSize"
        static let watchlistSortOrder = "watchlistSortOrder"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.maxWatchlistSize = (defaults.object(forKey: Keys.maxWatchlistSize) as? Int) ?? 50
        self.watchlistSortOrder = defaults.string(forKey: Keys.watchlistSortOrder)
            .flatMap(WatchlistSortOrder.init(rawValue:)) ?? .soonestFirst
    }
}
