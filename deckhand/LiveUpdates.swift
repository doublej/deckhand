import ActivityKit
import DeckhandKit
import Foundation
import SwiftUI

/// Keeps a Live Activity on the Lock Screen saying whether anything on the Mac is waiting.
///
/// The app cannot do this itself. It is asleep most of the time, and iOS gives a backgrounded
/// app no promise of running again soon — so the *daemon* drives the card, over APNs, and this
/// type exists only to hand it the two tokens that let it. Losing them is the failure mode
/// worth guarding: they change without warning, so both streams are watched for as long as the
/// app lives rather than read once at launch.
@MainActor
@Observable
final class LiveUpdates {
    private(set) var running = false
    private(set) var trouble: String?
    private var sent: Set<String> = []
    private var send: ((String, String) async throws -> Void)?

    /// `register` is passed in rather than reached for so this stays testable and so a token
    /// arriving before the app is paired is simply dropped rather than lost.
    func begin(register: @escaping (String, String) async throws -> Void) {
        send = register
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            trouble = "Live Activities are switched off for Deckhand in Settings"
            return
        }
        watchStartTokens()
        adopt()
    }

    /// A push-to-start token lets the Mac raise the card when there is none — after the system
    /// has ended one, after a reboot, after the app was force-quit. Without it the card only
    /// ever appears while the app is open, which defeats the point of it.
    private func watchStartTokens() {
        Task {
            for await data in Activity<Deck>.pushToStartTokenUpdates {
                await hand(data, kind: "start")
            }
        }
    }

    /// Nothing is started from here. The Mac raises the card when a session actually stops
    /// and waits — that is the only moment it has anything to say. Asking for one at launch
    /// would put "Nothing waiting" on the Lock Screen for hours, which is a card that trains
    /// you to ignore it.
    ///
    /// What this does instead is watch for a card appearing, whoever raised it, and hand the
    /// Mac the token that updates that particular one.
    private func adopt() {
        for existing in Activity<Deck>.activities {
            running = true
            watch(existing)
        }
        Task {
            for await activity in Activity<Deck>.activityUpdates {
                running = true
                watch(activity)
            }
        }
    }

    private func watch(_ activity: Activity<Deck>) {
        Task {
            for await data in activity.pushTokenUpdates {
                await hand(data, kind: "activity")
            }
        }
    }

    /// APNs wants the token as hex. Sent once per distinct value: these streams re-emit.
    private func hand(_ data: Data, kind: String) async {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        guard !sent.contains(hex), let send else { return }
        do {
            try await send(hex, kind)
            sent.insert(hex)
            trouble = nil
        } catch {
            trouble = "The Mac did not take the Lock Screen token: \(error.localizedDescription)"
        }
    }
}
