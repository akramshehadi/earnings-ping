import SwiftUI

/// Placeholder popover content for the menu-bar item. The real surfaces — the
/// watchlist (issue 02) and the Itsycal-style month calendar (issue 06) — replace
/// the body here; for the shell it just proves the popover renders and exercises
/// the Dock-icon toggle end to end.
struct MenuContentView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.tint)
                Text("Earnings Ping")
                    .font(.headline)
            }

            Text("Watchlist and calendar arrive in a later build.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Show Dock icon", isOn: $settings.showDockIcon)
                .toggleStyle(.switch)

            Divider()

            Button("Quit Earnings Ping") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
    }
}
