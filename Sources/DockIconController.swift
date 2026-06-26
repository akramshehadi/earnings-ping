import AppKit

/// Flips the app between menu-bar-only and Dock-visible at runtime by changing
/// its activation policy. `.accessory` hides the Dock icon (agent app);
/// `.regular` shows it. The change takes effect live, with no relaunch.
@MainActor
enum DockIconController {
    static func apply(showDockIcon: Bool) {
        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)

        // Switching to `.regular` from an agent state doesn't always bring the
        // app forward; nudging activation makes the new Dock icon appear
        // promptly and behave like a normal foreground app.
        if policy == .regular {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
