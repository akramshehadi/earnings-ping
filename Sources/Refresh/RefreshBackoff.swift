import Foundation

/// Exponential backoff for retrying after a *transient* refresh failure
/// (network / rate limit). Pure, so the schedule is unit-testable.
enum RefreshBackoff {
    static let base: TimeInterval = 30          // first retry, seconds
    static let cap: TimeInterval = 30 * 60      // never wait longer than 30 min

    /// Delay before the `failureCount`-th consecutive retry (1-based):
    /// 30s, 60s, 120s, … capped at 30 min.
    static func interval(failureCount: Int) -> Duration {
        let n = max(failureCount, 1)
        let seconds = min(base * pow(2, Double(n - 1)), cap)
        return .seconds(seconds)
    }
}
