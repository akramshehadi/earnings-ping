import AppKit
import SwiftUI

/// Opens the Settings window for this menu-bar-only (`LSUIElement`) app.
///
/// SwiftUI's `Settings` scene can't be opened here: an agent app has no
/// application menu to host the "Settings…" item, and the programmatic openers
/// (`SettingsLink`, `@Environment(\.openSettings)`) don't work from a Dock-less
/// `MenuBarExtra` — `openSettings` is broken outright on macOS 26 (FB10184971).
/// So we host the same `SettingsView` in an AppKit window we control, which
/// opens identically from the popover buttons and from first-run launch code.
@MainActor
final class SettingsWindowOpener {
    static let shared = SettingsWindowOpener()

    private var window: NSWindow?

    private init() {}

    /// Shows the (lazily built) Settings window and brings the otherwise
    /// inactive agent app to the front so it can take keyboard focus.
    func open(environment: AppEnvironment) {
        if window == nil {
            window = makeWindow(environment: environment)
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Dismisses the Settings window. The instance is kept (`isReleasedWhenClosed`
    /// is false) so a later `open` reuses it. Driven by the view's "Done" button.
    func close() {
        window?.close()
    }

    private func makeWindow(environment: AppEnvironment) -> NSWindow {
        let root = SettingsView()
            .environmentObject(environment)
            .environmentObject(environment.settings)
            .environmentObject(environment.loginItem)

        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "Earnings Ping Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        // Reuse one instance across opens so closing the window doesn't tear it
        // down (and so the window remembers its position via the autosave name).
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("EarningsPingSettingsWindow")
        window.center()
        return window
    }
}
