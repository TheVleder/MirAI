import Foundation
import UserNotifications

/// Manages daily reminder notifications for MirAI.
@MainActor
final class NotificationManager {

    static let shared = NotificationManager()

    /// Request notification permission and schedule daily reminder
    func setupDailyReminder() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
                self.scheduleDailyReminder()
            }
        }
    }

    /// Schedule a daily notification at 9 AM
    private func scheduleDailyReminder() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        // Only schedule if user opted in
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else { return }

        let content = UNMutableNotificationContent()
        content.title = "MirAI"
        content.body = [
            "Ready to chat? Your AI is waiting.",
            "What's on your mind today?",
            "Tap to start a voice conversation.",
            "Your private AI assistant is here for you.",
            "Let's talk! No data leaves your device."
        ].randomElement()!
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = 9
        dateComponents.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: "mirai.daily.reminder",
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    /// Toggle notifications on/off
    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "notificationsEnabled")
        if enabled {
            setupDailyReminder()
        } else {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
    }

    /// Check if notifications are enabled
    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "notificationsEnabled")
    }
}
