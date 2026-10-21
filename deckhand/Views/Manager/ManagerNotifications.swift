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

    /// What a tapped notification is about: the manager's chat, or one session's.
    enum Target: Equatable {
        case manager
        case session(String)

        /// `deckhand: manager` from the manager, `session: <id>` from anything about one session.
        init?(_ info: [AnyHashable: Any]) {
            if let session = info["session"] as? String, !session.isEmpty {
                self = .session(session)
            } else if info["deckhand"] as? String == "manager" {
                self = .manager
            } else {
                return nil
            }
        }
    }

    private var register: ((String) async throws -> Void)?
    private var opened: ((Target) -> Void)?
    /// Whether that chat is on screen right now. Its notification is then dropped in the
    /// foreground: the words are already arriving in front of the person.
    private var showing: ((Target) -> Bool)?
    /// A tap that arrived before the app had a model to act on it — every tap that launches the
    /// app cold, since iOS hands it over during launch and the scene's `.task` runs later.
    private var waiting: Target?

    /// From `AppDelegate`, at launch. The delegate has to be in place before launch finishes or
    /// the tap that launched the app is delivered to nobody — which is what opening the app
    /// "wherever it was" was.
    func listen() {
        UNUserNotificationCenter.current().delegate = self
    }

    func begin(register: @escaping (String) async throws -> Void,
               opened: @escaping (Target) -> Void,
               showing: @escaping (Target) -> Bool) {
        self.register = register
        self.opened = opened
        self.showing = showing
        listen()
        if let waiting {
            self.waiting = nil
            opened(waiting)
        }
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

    /// Shown in the foreground too — a banner over the rail or over another session is exactly
    /// the case it is for — except over the chat it came from. The Mac guesses whether the panel
    /// is open from how recently it polled, and a guess was what buzzed a person mid-sentence;
    /// the phone knows.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let target = Target(notification.request.content.userInfo)
        let onScreen = await MainActor.run { target.map { showing?($0) ?? false } ?? false }
        return onScreen ? [] : [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        // A decision's own button is answered where it was pressed (`DecisionNotes`).
        if await DecisionNotes.answered(response) { return }
        guard let target = Target(response.notification.request.content.userInfo) else { return }
        await MainActor.run { tapped(target) }
    }

    private func tapped(_ target: Target) {
        if let opened { opened(target) } else { waiting = target }
    }
}
