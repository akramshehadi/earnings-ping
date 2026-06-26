import Foundation

/// Result of validating a proposed Watchlist addition.
enum WatchlistAddOutcome: Equatable {
    case ok
    case duplicate(String)
    case full(Int)
}

/// Pure Watchlist logic, kept out of the view so it can be unit-tested:
/// add-validation and display sorting.
enum WatchlistOperations {
    /// Whether `symbol` may be added, given the symbols already present and the
    /// configured cap. Comparison is case-insensitive.
    static func validateAdd(
        symbol: String,
        existingSymbols: [String],
        maxSize: Int
    ) -> WatchlistAddOutcome {
        let normalized = symbol.uppercased()
        if existingSymbols.contains(where: { $0.uppercased() == normalized }) {
            return .duplicate(normalized)
        }
        if existingSymbols.count >= maxSize {
            return .full(maxSize)
        }
        return .ok
    }

    /// Order tickers for display. `soonestFirst` puts the nearest upcoming event
    /// first and tickers with no event last; `alphabetical` sorts by symbol.
    /// Ties break alphabetically by symbol.
    static func sorted(_ tickers: [Ticker], by order: WatchlistSortOrder) -> [Ticker] {
        switch order {
        case .alphabetical:
            return tickers.sorted { $0.symbol < $1.symbol }
        case .soonestFirst:
            return tickers.sorted { lhs, rhs in
                switch (lhs.event?.date, rhs.event?.date) {
                case let (l?, r?):
                    return l == r ? lhs.symbol < rhs.symbol : l < r
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.symbol < rhs.symbol
                }
            }
        }
    }
}
