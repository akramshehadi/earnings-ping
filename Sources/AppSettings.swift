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
    /// When `true`, the app shows a Dock icon (activation policy `.regular`);
    /// when `false`, it stays a menu-bar-only agent (`.accessory`). Default off.
    @Published var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: Keys.showDockIcon) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let showDockIcon = "showDockIcon"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.showDockIcon = defaults.bool(forKey: Keys.showDockIcon)
    }
}
