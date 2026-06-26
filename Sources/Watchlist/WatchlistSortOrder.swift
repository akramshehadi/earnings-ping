import Foundation

/// How the Watchlist is ordered. Default is soonest upcoming Earnings Event
/// first; alphabetical is the toggle.
enum WatchlistSortOrder: String, CaseIterable, Identifiable, Sendable {
    case soonestFirst
    case alphabetical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .soonestFirst: return "Soonest first"
        case .alphabetical: return "A–Z"
        }
    }
}
