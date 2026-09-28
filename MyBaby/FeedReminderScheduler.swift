import Foundation
import UserNotifications

/// Schedules a local "time for a feed?" notification a set time after the last feed.
enum FeedReminderScheduler {
    private static let identifier = "feed-reminder"

    /// Interval choices offered in Settings, in minutes.
    static let intervalOptions = [120, 150, 180, 210, 240]
    static let defaultMinutes = 180

    /// Asks for notification permission. Returns true if reminders can be delivered.
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces any pending reminder with one based on the latest feed.
    static func reschedule(lastFeed: Date?, babyName name: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKey.feedRemindersEnabled), let lastFeed else { return }

        let storedMinutes = defaults.integer(forKey: SettingsKey.feedReminderMinutes)
        let minutes = storedMinutes > 0 ? storedMinutes : defaultMinutes
        let fireDate = lastFeed.addingTimeInterval(TimeInterval(minutes * 60))
        let delay = fireDate.timeIntervalSinceNow
        guard delay > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time for a feed?"
        content.body = name.isEmpty
            ? "It's been \(formatted(minutes: minutes)) since the last feed."
            : "It's been \(formatted(minutes: minutes)) since \(name)'s last feed."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    /// "3 hours" / "2 hours 30 minutes".
    static func formatted(minutes: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) minutes"
    }
}
