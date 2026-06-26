import AppKit

/// Opens the SwiftUI `Settings` scene window and brings it (and the otherwise
/// Dock-less agent app) to the front.
///
/// `LSUIElement` apps aren't active by default, so a plain settings action can
/// open the window behind everything; the explicit `activate` avoids that. The
/// `showSettingsWindow:` responder action is what the `Settings` scene installs
/// on macOS 14+, and routing it through `nil` lets AppKit find that handler.
enum SettingsWindowOpener {
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
