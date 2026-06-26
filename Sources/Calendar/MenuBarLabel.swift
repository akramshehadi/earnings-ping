import SwiftData
import SwiftUI

/// The `MenuBarExtra` label. Normally the app glyph; when any watched Earnings
/// Event enters the Imminent Window it gains a small countdown badge — the days
/// until the soonest such event, or a filled dot when that event is today
/// (CONTEXT/PRD: badge the icon "countdown / dot").
///
/// Reactive on two axes: `@Query` refires when a refresh or Date Change moves an
/// event's `date`, and a periodic clock tick re-evaluates the window as calendar
/// days elapse (so the badge appears/clears across midnight without a data change).
struct MenuBarLabel: View {
    @Query private var events: [EarningsEvent]
    @EnvironmentObject private var settings: AppSettings

    /// Re-evaluated on each tick so the countdown stays correct as days pass.
    @State private var now = Date()

    private let window = ImminentWindow()
    /// Half-hourly is plenty for a day-granularity countdown and keeps the menu
    /// bar cheap; the boundary that matters (midnight) is crossed within 30 min.
    private let clock = Timer.publish(every: 1800, on: .main, in: .common).autoconnect()

    var body: some View {
        badgeView(for: state)
            .onReceive(clock) { now = $0 }
    }

    private var state: BadgeState {
        window.badge(
            for: events.map(\.date),
            now: now,
            thresholdDays: settings.imminentWindowDays
        )
    }

    @ViewBuilder
    private func badgeView(for state: BadgeState) -> some View {
        switch state {
        case .none:
            Image(systemName: "calendar.badge.clock")
                .accessibilityLabel("Earnings Ping")
        case .imminent(let days):
            Image(systemName: "calendar.badge.clock")
                .overlay(alignment: .topTrailing) { countdown(days) }
                .accessibilityLabel(accessibilityText(days))
        }
    }

    /// Days-until as a tiny numeric badge, or a filled dot when the event is
    /// today (0 days). Sized to read in the menu bar's template rendering.
    @ViewBuilder
    private func countdown(_ days: Int) -> some View {
        if days <= 0 {
            Circle()
                .frame(width: 6, height: 6)
                .offset(x: 3, y: -2)
        } else {
            Text("\(days)")
                .font(.system(size: 8, weight: .bold))
                .padding(1)
                .background(Circle().fill(.background))
                .offset(x: 4, y: -3)
        }
    }

    private func accessibilityText(_ days: Int) -> String {
        switch days {
        case ...0: return "Earnings Ping — earnings today"
        case 1: return "Earnings Ping — earnings tomorrow"
        default: return "Earnings Ping — earnings in \(days) days"
        }
    }
}
