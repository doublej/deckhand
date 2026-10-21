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
///
/// A notify (`POST /notify`, `CallbackNote`) is the one alert here with no session: Allow and
/// Deny, signed the same way, and the Mac answers whoever on it asked.
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
            UNNotificationCategory(identifier: Note.Category.text, actions: [reply], intentIdentifiers: []),
            allowDeny
        ])
    }

    /// A notify's Allow and Deny, behind the same unlock as a decision's Approve and Deny.
    private static var allowDeny: UNNotificationCategory {
        let allow = UNNotificationAction(identifier: CallbackNote.Action.approve, title: "Allow",
                                         options: [.authenticationRequired])
        let refuse = UNNotificationAction(identifier: CallbackNote.Action.deny, title: "Deny",
                                          options: [.authenticationRequired, .destructive])
        return UNNotificationCategory(identifier: CallbackNote.Category.allowDeny,
                                      actions: [allow, refuse], intentIdentifiers: [])
    }

    /// Answer the button that was pressed. True when it was a decision's own button, answered or
    /// refused — the caller then has nothing left to do. False for a tap on the notification,
    /// which the delegate opens like any other.
    static func answered(_ response: UNNotificationResponse) async -> Bool {
        let content = response.notification.request.content
        if let note = CallbackNote(userInfo: content.userInfo),
           let action = CallbackNote.action(for: response.actionIdentifier) {
            await send(action, for: note)
            return true
        }
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

    /// The Mac calls the asker back; only a refusal, or a caller that did not take it, is said.
    private static func send(_ action: String, for note: CallbackNote) async {
        guard let client = ServerSettings.load().client() else {
            await tell(note, "Deckhand has no Mac to reach — open the app and pair it.")
            return
        }
        do {
            try await PhoneKey.answerNotify(with: client, id: note.id, action: action)
        } catch {
            await tell(note, why(error))
        }
    }

    /// A refusal has to be said where the button was, because nothing else is on screen.
    private static func tell(_ note: DecisionNote, _ why: String) async {
        await tell(note.question, why, id: "decision-\(note.session)-\(note.artifact)",
                   thread: note.session, userInfo: ["session": note.session])
    }

    private static func tell(_ note: CallbackNote, _ why: String) async {
        await tell(note.question, why, id: "notify-\(note.id)", thread: "notify")
    }

    private static func tell(_ question: String?, _ why: String, id: String, thread: String,
                             userInfo: [String: String] = [:]) async {
        let content = UNMutableNotificationContent()
        content.title = "Not answered"
        content.body = [question, why].compactMap { $0 }.joined(separator: " — ")
        content.threadIdentifier = thread
        content.userInfo = userInfo
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
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
