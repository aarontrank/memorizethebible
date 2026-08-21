import Foundation
import BibleCore
import UserNotifications

/// Local reminders (§10). No push, no server, no third-party service.
///
/// The rule: on every foreground and background, cancel everything pending and
/// schedule exactly one notification for 24 hours of inactivity, clamped to the
/// user's chosen time of day. Net effect — the user is notified only after a
/// full day away.
///
/// This is only the `UserNotifications` plumbing; the rule itself lives in
/// `ReminderPlanner`, where it is unit tested.
struct ReminderScheduler {
    static let identifier = "daily-reminder"

    private let center: UNUserNotificationCenter?

    init(center: UNUserNotificationCenter? = .current()) {
        self.center = center
    }

    /// §10: requested only when the user turns the toggle on, never at launch.
    func requestAuthorization() async -> Bool {
        guard let center else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func cancelAll() async {
        center?.removeAllPendingNotificationRequests()
    }

    func reschedule(for progress: ProgressSnapshot, content: ContentStore, clock: any AppClock) async {
        await cancelAll()
        guard progress.notificationsEnabled, let center else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        else { return }

        guard
            let fireDate = ReminderPlanner.nextFireDate(
                after: clock.now,
                at: progress.reminderTime,
                calendar: clock.calendar
            )
        else { return }

        let notification = UNMutableNotificationContent()
        notification.title = "Memorize The Bible"
        notification.body = ReminderPlanner.message(
            progress: progress,
            content: content,
            clock: clock
        )

        let components = clock.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: notification,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
    }
}
