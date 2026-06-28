import SwiftUI

/// A session-code badge ("BMO", "AMC", "DMH", "Time TBD") that reveals its
/// meaning in a small tooltip on hover.
///
/// We can't use SwiftUI's `.help()` here: the whole UI lives inside a
/// `MenuBarExtra(.window)`, and that window never displays AppKit tooltips, so
/// `.help()` silently shows nothing (it still feeds VoiceOver, hence the
/// `accessibilityLabel` below). Plain `.onHover` *does* fire in this window, so
/// we roll our own floating tooltip.
struct SessionBadge: View {
    /// How the badge itself is drawn — matches the two existing call sites.
    enum Style {
        case plain    // bare secondary text (Watchlist)
        case capsule  // pill on a quaternary fill (Calendar day strip)
    }

    let session: Session
    var style: Style = .plain

    @State private var isHovering = false

    var body: some View {
        badge
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .overlay(alignment: tooltipAnchor) { tooltip }
            .animation(.easeInOut(duration: 0.1), value: isHovering)
            // `.help()` would normally expose this to VoiceOver; keep that here.
            .accessibilityLabel(session.helpText)
    }

    @ViewBuilder
    private var badge: some View {
        switch style {
        case .plain:
            Text(session.shortLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .capsule:
            Text(session.shortLabel)
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(.quaternary))
        }
    }

    @ViewBuilder
    private var tooltip: some View {
        if isHovering {
            Text(session.helpText)
                .font(.caption2)
                // The overlay is proposed the badge's (tiny) width; without
                // `fixedSize` the text would wrap to a few characters wide.
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                .offset(y: -26)            // float just above the badge
                .allowsHitTesting(false)   // pointer stays on the badge: no flicker
                .transition(.opacity)
                .zIndex(1)
        }
    }

    /// Open the tooltip toward the window's centre so the popover edge doesn't
    /// clip it: Watchlist badges hug the right edge (open left), Calendar badges
    /// sit at the left (open right).
    private var tooltipAnchor: Alignment {
        switch style {
        case .plain: return .topTrailing
        case .capsule: return .topLeading
        }
    }
}
