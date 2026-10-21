import DeckhandKit
import UIKit
import UserNotifications

/// A decision's notification, answered from the notification itself.
///
/// The daemon sends one alert per decision with `aps.category` set to one of three categories;
/// this registers what each one offers and answers a button press by signing it with the phone's
/// key (`PhoneKey`). Every button needs the phone unlocked: the key's keychain slot opens only
/// then, and a Yes from a phone face-up on a table is the tap this exists to make deliberate.
///
/// A pick has no buttons — a notification has room for a few short ones and a pick's rows are
/// whatever an agent wrote — so a tap opens the slip, through the notification's own `link`.
enum DecisionNotes {
    /// At launch, before anything can be delivered (`AppDelegate`).
    static func register() {
        typealias Note = DecisionNote
        let unlocked: UNNotificationActionOptions = [.authenticationRequired]
        let approve = UNNotificationAction(identifier: Note.Action.approve, title: "Approve",
                                           options: unlocked)
        let deny = UNNotificationAction(identifier: Note.Action.deny, title: "Deny",
                                        options: [.authenticationRequired, .destructive])
        let reply = UNTextInputNotificationAction(identifier: Note.Action.reply, title: "Reply",
                                                  options: unlocked, textInputButtonTitle: "Send",
                                                  textInputPlaceholder: "Your answer")
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: Note.Category.confirm, actions: [approve, deny, reply],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: Note.Category.pick, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Note.Category.text, actions: [reply], intentIdentifiers: [])
        ])
    }

    /// Answer the button that was pressed. True when it was a decision's own button, answered or
    /// refused — the caller then has nothing left to do. False for a tap on the notification,
    /// which the delegate opens like any other.
    static func answered(_ response: UNNotificationResponse) async -> Bool {
        let content = response.notification.request.content
        guard let note = DecisionNote(userInfo: content.userInfo),
              let value = DecisionNote.value(
                category: content.categoryIdentifier, action: response.actionIdentifier,
                typed: (response as? UNTextInputNotificationResponse)?.userText
              ) else { return false }
        await send(value, for: note)
        return true
    }

    private static func send(_ value: JSONValue, for note: DecisionNote) async {
        guard let client = ServerSettings.load().client() else {
            await tell(note, "Deckhand has no Mac to reach — open the app and pair it.")
            return
        }
        do {
            let sent = try await PhoneKey.answer(with: client, artifact: note.artifact,
                                                 in: note.session, hash: note.hash, value: value)
            if !sent.went {
                await tell(note, "Answered, but the session was not told: "
                    + (sent.stoppedBy.map { "\($0) stopped it" } ?? sent.deliveryError ?? "no route"))
            }
        } catch {
            await tell(note, why(error))
        }
    }

    /// A refusal has to be said where the button was, because nothing else is on screen.
    private static func tell(_ note: DecisionNote, _ why: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Not answered"
        content.body = [note.question, why].compactMap { $0 }.joined(separator: " — ")
        content.threadIdentifier = note.session
        content.userInfo = ["session": note.session]
        let request = UNNotificationRequest(identifier: "decision-\(note.session)-\(note.artifact)",
                                            content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func why(_ error: Error) -> String {
        switch error {
        case DeckhandError.unauthorized: "Token rejected by the Mac"
        case DeckhandError.notLive: "That slip or its session is gone"
        case let refused as DeckhandError: refused.detail ?? "The Mac refused it"
        default: error.localizedDescription
        }
    }
}
