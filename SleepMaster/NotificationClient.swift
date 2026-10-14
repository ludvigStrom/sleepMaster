import Foundation
import UserNotifications

enum NotificationAction {
    static let timerCategory = "sleepmaster.timer.warning"
    static let timerRequest = "sleepmaster.timer.warning"
    static let pauseRequest = "sleepmaster.paused"
    static let extend30 = "extend30"
    static let keepAwake = "keepAwake"
    static let letSleep = "letSleep"
}

@MainActor
protocol NotificationPosting: AnyObject {
    func requestPermissionIfNeeded()
    func scheduleTimerWarning(at date: Date)
    func cancelTimerWarning()
    func notifyPausedOnBattery()
}

@MainActor
final class IdleNotificationClient: NotificationPosting {
    func requestPermissionIfNeeded() {}
    func scheduleTimerWarning(at date: Date) {}
    func cancelTimerWarning() {}
    func notifyPausedOnBattery() {}
}

@MainActor
final class UserNotificationClient: NotificationPosting {
    private var hasRequested = false
    private let center = UNUserNotificationCenter.current()

    static func registerCategories() {
        let extend = UNNotificationAction(
            identifier: NotificationAction.extend30,
            title: "+30 min",
            options: []
        )
        let keepAwake = UNNotificationAction(
            identifier: NotificationAction.keepAwake,
            title: "Keep awake",
            options: []
        )
        let letSleep = UNNotificationAction(
            identifier: NotificationAction.letSleep,
            title: "Let it sleep",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: NotificationAction.timerCategory,
            actions: [extend, keepAwake, letSleep],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func requestPermissionIfNeeded() {
        guard !hasRequested else { return }
        hasRequested = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func scheduleTimerWarning(at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Sleepmaster"
        content.body = "Timer ending soon. The Mac will be allowed to sleep."
        content.categoryIdentifier = NotificationAction.timerCategory
        content.sound = .default

        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: NotificationAction.timerRequest,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func cancelTimerWarning() {
        center.removePendingNotificationRequests(withIdentifiers: [NotificationAction.timerRequest])
        center.removeDeliveredNotifications(withIdentifiers: [NotificationAction.timerRequest])
    }

    func notifyPausedOnBattery() {
        let content = UNMutableNotificationContent()
        content.title = "Sleepmaster paused"
        content.body = "On battery — sleep is allowed until you plug in."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: NotificationAction.pauseRequest,
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}
