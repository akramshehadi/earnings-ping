import Combine
import SwiftUI

/// Composition root: the single object that wires the app's collaborators
/// together and hands them to the SwiftUI view tree via `@EnvironmentObject`.
///
/// For the menu-bar shell (issue 01) this only carries `AppSettings` and keeps
/// the Dock-icon activation policy in sync with the user's preference. Later
/// issues hang their dependencies here (persistence store, earnings provider,
/// refresh engine, notification scheduler, …).
@MainActor
final class AppEnvironment: ObservableObject {
    let settings: AppSettings

    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings? = nil) {
        self.settings = settings ?? AppSettings()
    }

    /// Apply launch-time UI state and observe future changes. Call once, after
    /// the app finishes launching.
    func bootstrap() {
        DockIconController.apply(showDockIcon: settings.showDockIcon)

        // Keep the Dock icon in sync whenever the preference changes at runtime,
        // regardless of which surface (menu, future Settings window) flips it.
        settings.$showDockIcon
            .receive(on: RunLoop.main)
            .sink { showDockIcon in
                DockIconController.apply(showDockIcon: showDockIcon)
            }
            .store(in: &cancellables)
    }
}
