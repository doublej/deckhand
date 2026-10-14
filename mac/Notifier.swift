import DeckhandKit
import Foundation
import UserNotifications

/// What reaches the person at the Mac when no panel is being looked at.
///
/// Two sources and no decisions of its own. A session's card is whatever the daemon's `push/`
/// raised — the same cards the Lock Screen gets, read off `GET /alerts`, so a folder set quiet is
/// quiet here too. The manager's replies are shown only while no panel is looked at, which the
/// desk decides. Only `asking` makes a noise, the Lock Screen's own rule.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// What a clicked notification is about.
    enum Target: Equatable {
        case manager
        case session(String)
    }

    var opened: ((Target) -> Void)?

    func begin() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        Task { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
    }

    func show(_ alert: SessionAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.name
        content.body = alert.line
        content.threadIdentifier = alert.session
        content.userInfo = ["session": alert.session]
        if alert.isAsking { content.sound = .default }
        post("alert-\(alert.session)-\(alert.id)", content)
    }

    func show(_ entry: ManagerEntry) {
        let content = UNMutableNotificationContent()
        content.title = "Manager"
        content.body = entry.text
        content.threadIdentifier = "manager"
        content.userInfo = ["deckhand": "manager"]
        content.sound = .default
        post("manager-\(entry.id)", content)
    }

    private func post(_ identifier: String, _ content: UNNotificationContent) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Shown in the front too: a card about a session is news whichever app is in front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let session = response.notification.request.content.userInfo["session"] as? String
        await MainActor.run { opened?(session.map(Target.session) ?? .manager) }
    }
}
