import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private var hasRequestedAuthorization = false

    private init() {}

    func prepareIfNeeded() async {
        guard !hasRequestedAuthorization else { return }
        let center = UNUserNotificationCenter.current()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            #if DEBUG
            print("Notification permission request failed: \(error)")
            #endif
        }
        hasRequestedAuthorization = true
    }

    func notifySleepDetected() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                    settings.authorizationStatus == .provisional ||
                    settings.authorizationStatus == .ephemeral else { return }
            #if DEBUG
            print("[NoSleepy][Notify] Scheduling time-sensitive alert")
            #endif

            let content = UNMutableNotificationContent()
            content.title = "Wake up!"
            content.body = "NoSleepy noticed you might be asleep. Time to move!"
            content.sound = .default
            if #available(iOS 15.0, *) {
                // Time-sensitive alerts surface quickly and can break through Focus if allowed by the user.
                content.interruptionLevel = .timeSensitive
            }

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            center.add(request)
        }
    }
}

