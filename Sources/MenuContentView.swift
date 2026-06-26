import SwiftUI

/// Popover content for the menu-bar item: the Itsycal-style month calendar, the
/// Watchlist, and a compact freshness/actions footer.
struct MenuContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var refresh: RefreshCoordinator

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                MonthCalendarView()
                    .tabItem { Label("Calendar", systemImage: "calendar") }
                WatchlistView(symbolSearch: environment.symbolSearch)
                    .tabItem { Label("Watchlist", systemImage: "list.bullet") }
            }
            // Keeps the popover from collapsing and limits the height jump when
            // switching between the (taller) calendar and the watchlist.
            .frame(minHeight: 360)

            Divider()
            footer
        }
        .frame(width: 320)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            status
            Spacer(minLength: 8)
            Button {
                refresh.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(refresh.isRefreshing)
            .help("Refresh earnings dates now")

            Button {
                SettingsWindowOpener.shared.open(environment: environment)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Compact freshness / failure indicator (CONTEXT: stale "updated X ago").
    @ViewBuilder
    private var status: some View {
        if refresh.isRefreshing {
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Updating…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if refresh.needsAPIKey {
            Button {
                SettingsWindowOpener.shared.open(environment: environment)
            } label: {
                Label("Add Finnhub key", systemImage: "key")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("Open Settings to add your Finnhub API key")
        } else if let summary = refresh.lastErrorSummary {
            Label(summary, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else if let last = refresh.lastSuccessfulRefresh {
            Text("Updated \(last, format: .relative(presentation: .named))")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Not updated yet")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
