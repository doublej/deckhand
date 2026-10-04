import DeckhandKit
import UIKit
import UserNotifications

/// The manager's messages, as notifications, for when its panel is not on screen.
///
/// The daemon decides when to send one — only while no phone is polling the panel — and does the
/// sending over APNs, for the reason `LiveUpdates` gives: a backgrounded app has no promise of
/// running again. All this does is ask once for permission, hand the Mac the app's device token,
/// and open the panel when one is tapped. Turning them off is iOS's own Settings switch.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private var register: ((String) async throws -> Void)?
    private var opened: (() -> Void)?

    func begin(register: @escaping (String) async throws -> Void, opened: @escaping () -> Void) {
        self.register = register
        self.opened = opened
        UNUserNotificationCenter.current().delegate = self
        Task {
            let allowed = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            guard allowed == true else { return }
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// From `AppDelegate`, which is where UIKit hands the token over.
    func received(token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        Task { try? await register?(hex) }
    }

    /// Shown in the foreground as well: the Mac only sends one while the panel is not showing,
    /// so a banner over the rail is exactly the case it is for.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let manager = response.notification.request.content.userInfo["deckhand"] as? String
        guard manager == "manager" else { return }
        await MainActor.run { opened?() }
    }
}
