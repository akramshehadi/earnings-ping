import SwiftUI

/// App entry point. A menu-bar-only (`LSUIElement`) SwiftUI app whose single
/// scene is a `MenuBarExtra` rendering its content as a click-through popover.
///
/// The composition root (`AppEnvironment`) is owned by `AppDelegate` so it can be
/// bootstrapped in `applicationDidFinishLaunching` — before any window appears —
/// which is where the refresh engine is started.
@main
struct EarningsPingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(appDelegate.environment)
                .environmentObject(appDelegate.environment.settings)
                .environmentObject(appDelegate.environment.refreshCoordinator)
                .modelContainer(appDelegate.environment.modelContainer)
        } label: {
            MenuBarLabel()
                .environmentObject(appDelegate.environment.settings)
                .modelContainer(appDelegate.environment.modelContainer)
        }
        .menuBarExtraStyle(.window)
    }
}
