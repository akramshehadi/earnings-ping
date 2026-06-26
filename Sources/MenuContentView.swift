import SwiftUI

/// Popover content for the menu-bar item: the Watchlist plus a compact footer.
/// The Itsycal-style month calendar (issue 06) joins this layout later.
struct MenuContentView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        VStack(spacing: 0) {
            WatchlistView(symbolSearch: environment.symbolSearch)
            Divider()
            footer
        }
        .frame(width: 320)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
