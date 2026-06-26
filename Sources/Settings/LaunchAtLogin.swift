import Foundation
import ServiceManagement

/// Registers/unregisters the app as a login item. Behind a protocol so the
/// settings controller can be tested without touching the real login database.
protocol LoginItemControlling: Sendable {
    /// Whether the app is currently registered to launch at login.
    var isEnabled: Bool { get }
    /// Register (or unregister) the app as a login item.
    func setEnabled(_ enabled: Bool) throws
}

/// `SMAppService`-backed login item for the main app bundle (macOS 13+).
///
/// No helper target or extra entitlement is needed for `.mainApp`; registration
/// only sticks for a properly located, signed build, so callers must surface any
/// thrown error rather than assume success.
struct LaunchAtLogin: LoginItemControlling {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status == .enabled else { return }
            try service.unregister()
        }
    }
}
