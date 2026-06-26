import Combine
import Foundation

/// Observable adapter the settings UI binds to: reflects the login-item state,
/// applies toggles through `LoginItemControlling`, and surfaces any failure
/// instead of silently leaving the toggle out of sync.
@MainActor
final class LoginItemController: ObservableObject {
    /// Mirrors the registered state; the source of truth is the service, which
    /// this re-reads after every mutation so the toggle can't drift from reality.
    @Published private(set) var isEnabled: Bool
    /// Short, user-facing description of the most recent failure, if any.
    @Published private(set) var lastError: String?

    private let service: any LoginItemControlling

    init(service: any LoginItemControlling = LaunchAtLogin()) {
        self.service = service
        self.isEnabled = service.isEnabled
    }

    /// Register/unregister, then resync `isEnabled` from the service so a failed
    /// or no-op change leaves the toggle showing the true state.
    func setEnabled(_ enabled: Bool) {
        do {
            try service.setEnabled(enabled)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        isEnabled = service.isEnabled
    }

    /// Re-read the registered state (e.g. when the settings window reappears).
    func refresh() {
        isEnabled = service.isEnabled
    }
}
