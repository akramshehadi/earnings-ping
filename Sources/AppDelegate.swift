import AppKit

/// Owns the composition root so it is created once, up front, and lives for the
/// app's lifetime. Kicks off the refresh engine at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Starts the launch refresh and begins watching for the timer,
        // wake-from-sleep, and network-reconnect triggers.
        environment.refreshCoordinator.start()

        // First run: with no key the app can't fetch anything, so present the
        // Settings window (in its welcome/onboarding state) up front. Deferred a
        // runloop turn so the `Settings` scene's action target is registered.
        if !environment.hasAPIKey {
            DispatchQueue.main.async { SettingsWindowOpener.open() }
        }
    }
}
