import Foundation
import UserNotifications

/// A notification to deliver. `fireDate == nil` means deliver immediately (used
/// for Date-Change alerts); otherwise it is scheduled for that instant.
struct PendingNotification: Equatable, Sendable {
    let id: String
    let title: String
    let body: String
    let fireDate: Date?
}

/// Seam over `UNUserNotificationCenter` so the scheduler core is testable
/// without the real notification center (which requires a running app bundle).
/// All methods are best-effort and non-throwing — a denied or unavailable
/// center degrades gracefully to a no-op rather than surfacing an error.
protocol NotificationScheduling: Sendable {
    /// Request alert/sound authorization. Returns whether it was granted.
    func requestAuthorization() async -> Bool
    /// Identifiers of all currently-scheduled (not yet delivered) notifications.
    func pendingIdentifiers() async -> [String]
    /// Add (or, for a matching identifier, replace) a notification.
    func add(_ notification: PendingNotification) async
    /// Cancel scheduled notifications by identifier.
    func removePending(identifiers: [String]) async
}

/// Live adapter backed by the user notification center. Trigger date components
/// are built in the user's local calendar so a reminder fires at local wall
/// time. `UNUserNotificationCenter` is thread-safe, hence `@unchecked Sendable`.
final class UserNotificationCenterScheduler: NotificationScheduling, @unchecked Sendable {
    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    init(center: UNUserNotificationCenter = .current(), calendar: Calendar = .current) {
        self.center = center
        self.calendar = calendar
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func add(_ notification: PendingNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default

        let trigger: UNNotificationTrigger?
        if let fireDate = notification.fireDate {
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        } else {
            trigger = nil // deliver immediately
        }

        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    func removePending(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
