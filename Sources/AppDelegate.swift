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
        // Settings window (in its welcome/onboarding state) up front. The Keychain
        // check runs off the main thread (see `hasStoredAPIKey`): a stored key can
        // raise an ACL prompt, and reading it synchronously here would let that
        // modal freeze launch and hang `xcodebuild test`. The `await` also defers
        // the window past launch activation, replacing the old runloop hop.
        Task { [environment] in
            if await !environment.hasStoredAPIKey() {
                SettingsWindowOpener.shared.open(environment: environment)
            }
        }
    }
}
