import Foundation

/// Which part of the US trading day an `EarningsEvent` lands in. `unknown` means
/// the provider hasn't set a time yet ("time TBD") — the date is still shown.
enum Session: String, Codable, CaseIterable, Sendable {
    case bmo   // before market open
    case amc   // after market close
    case dmh   // during market hours
    case unknown

    /// Compact badge text for dense UI, e.g. "BMO".
    var shortLabel: String {
        switch self {
        case .bmo: return "BMO"
        case .amc: return "AMC"
        case .dmh: return "DMH"
        case .unknown: return "Time TBD"
        }
    }

    /// Human-readable description for detail views and notifications.
    var longLabel: String {
        switch self {
        case .bmo: return "Before market open"
        case .amc: return "After market close"
        case .dmh: return "During market hours"
        case .unknown: return "Time not set"
        }
    }
}
