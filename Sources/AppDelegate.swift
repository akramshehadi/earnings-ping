import AppKit

/// Owns the composition root and performs launch-time setup that must happen
/// before any UI is shown — notably applying the initial Dock-icon activation
/// policy so the app respects the user's `showDockIcon` preference from the
/// first frame.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment.bootstrap()
    }
}
