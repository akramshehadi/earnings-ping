import SwiftUI

/// Popover content for the menu-bar item: the Itsycal-style month calendar, the
/// Watchlist, and a compact freshness/actions footer.
struct MenuContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var refresh: RefreshCoordinator

    /// Which surface the popover shows. Replaces a native `TabView`: on macOS
    /// Tahoe the TabView's restyled bordered container collided with the popover
    /// — its top edge overlapped the segmented tab buttons and its bottom edge
    /// cut across the footer's Quit button. A custom segmented control gives us
    /// full control over chrome and padding across macOS versions.
    private enum Tab: Hashable { case calendar, watchlist }
    @State private var tab: Tab = .calendar

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                Text("Calendar").tag(Tab.calendar)
                Text("Watchlist").tag(Tab.watchlist)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Group {
                switch tab {
                case .calendar:
                    MonthCalendarView()
                case .watchlist:
                    WatchlistView(symbolSearch: environment.symbolSearch)
                }
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
