import AppKit
import UserNotifications

/// Result summary as a notification; an alert when notifications are not allowed.
@MainActor
enum Notifier {
    static func requestAuthorization() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) }
    }

    static func post(title: String, body: String, log: URL?) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else {
            JobWindow.alert(title, body + (log.map { "\n\nKayıt: \($0.path)" } ?? ""))
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
