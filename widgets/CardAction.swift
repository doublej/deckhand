import ActivityKit
import AppIntents
import DeckhandKit
import Foundation

/// The one thing a Lock Screen card may do: answer a yes-or-no slip, or a notify (`AnswerNotify`).
///
/// **A card answers only the question it shows.** The daemon puts a slip's id and buttons on a
/// card only for a confirm, and then the card's line *is* that slip's question — so a Yes is
/// never pressed under a sentence other than the one it answers. The answer goes through the
/// same route as the slip page's own buttons (`POST …/artifacts/{id}/answer`), as the person,
/// because it is the person.
///
/// What is still not here, by absence:
///
/// - **There is no Approve.** Answering a permission prompt is the keyboard route, and a card
///   carries one line of what the session said rather than the prompt it is blocked on. A slip is
///   different in kind: the agent wrote the question for the person, and the card shows all of it.
/// - **No Stop, `compact`, `clear` or `exit`.** Stop was here and was never pressed; the other
///   three cannot be undone or cost the session itself, and a Lock Screen has nowhere to ask first.
///
/// `LiveActivityIntent` rather than a plain `AppIntent`: the system performs one of these in the
/// **app's** process, so `ServerSettings.load()` reads the pairing the person typed into the app.
/// A plain `AppIntent` runs in the widget extension, which has a UserDefaults of its own and
/// would find no Mac to talk to without an App Group this project does not have.
///
/// The file lives under `widgets/` and is compiled into **both** targets (`project.yml`): the
/// widget names the intent in its `Button`, the app performs it, so each binary needs the type.
struct AnswerSlip: LiveActivityIntent {
    static var title: LocalizedStringResource { "Answer this slip" }
    static var description: IntentDescription? {
        IntentDescription("Answers a yes-or-no question a session asked on the phone.")
    }

    /// A Yes can do something that cannot be taken back — "Tag and push?" — and a phone face-up
    /// on a table takes stray taps. With Face ID this costs nothing when you are looking at it.
    ///
    /// ponytail: `.alwaysAllowed` if the unlock ever gets in the way on a real phone.
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    @Parameter(title: "Session")
    var session: String

    @Parameter(title: "Slip")
    var slip: String

    @Parameter(title: "Yes")
    var yes: Bool

    /// The page's hash when the slip is a decision — the card's state carries it — and the Yes is
    /// then signed with the phone's key over exactly that page. Nil for a Mac older than decisions.
    @Parameter(title: "Page")
    var hash: String?

    init() {}

    init(session: String, slip: String, hash: String?, yes: Bool) {
        self.session = session
        self.slip = slip
        self.hash = hash
        self.yes = yes
    }

    /// Answers, then says so on the card at once rather than when the Mac next sweeps. The Mac
    /// takes the card down, or moves it on to the next slip, a few seconds later.
    func perform() async throws -> some IntentResult {
        guard let client = ServerSettings.load().client() else { throw Trouble.noMac }
        let sent = try await answer(with: client)
        for card in Activity<Deck>.activities where card.attributes.session == session {
            var state = card.content.state
            let said = (yes ? state.accept : state.decline) ?? (yes ? "Yes" : "No")
            state.line = sent.went ? "You said \(said)." : "You said \(said) — the session was not told."
            state.kind = .finished
            state.slip = nil
            state.hash = nil
            await card.update(ActivityContent(state: state, staleDate: nil))
        }
        return .result()
    }

    /// A decision is signed with the phone's key; a slip from a Mac older than decisions goes the
    /// way it always did, by the route the person chose.
    private func answer(with client: DeckhandClient) async throws -> Delivery {
        guard let hash else {
            return try await client.answer(slip, in: session,
                                           valueJSON: yes ? #"{"answer":true}"# : #"{"answer":false}"#,
                                           route: Preferences.load().route)
        }
        do {
            return try await PhoneKey.answer(with: client, artifact: slip, in: session, hash: hash,
                                             value: .object(["answer": .bool(yes)]))
        } catch let refused as DecisionRefusal {
            throw Trouble.refused(refused.errorDescription ?? "The Mac refused it")
        }
    }
}

/// A notify's card (`POST /notify`): Yes is `approve` and No is `deny`, signed like a decision's
/// answer, and the Mac calls back whoever asked. The card has nothing left to say after that, so
/// it goes — the Mac's own end lands later and finds it gone.
struct AnswerNotify: LiveActivityIntent {
    static var title: LocalizedStringResource { "Answer this request" }
    static var description: IntentDescription? {
        IntentDescription("Allows or denies a request a program on the Mac sent the phone.")
    }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    @Parameter(title: "Request")
    var id: String

    @Parameter(title: "Yes")
    var yes: Bool

    init() {}

    init(id: String, yes: Bool) {
        self.id = id
        self.yes = yes
    }

    func perform() async throws -> some IntentResult {
        guard let client = ServerSettings.load().client() else { throw Trouble.noMac }
        do {
            try await PhoneKey.answerNotify(with: client, id: id, action: yes ? "approve" : "deny")
        } catch let refused as DecisionRefusal {
            throw Trouble.refused(refused.errorDescription ?? "The Mac refused it")
        } catch let refused as DeckhandError {
            throw Trouble.refused(refused.detail ?? "The Mac refused it")
        }
        for card in Activity<Deck>.activities where card.attributes.session == "notify:\(id)" {
            var state = card.content.state
            state.line = "You said \((yes ? state.accept : state.decline) ?? (yes ? "Yes" : "No"))."
            state.kind = .finished
            state.notify = nil
            await card.end(ActivityContent(state: state, staleDate: nil),
                           dismissalPolicy: .after(.now + 4))
        }
        return .result()
    }
}

/// Why a card's button did nothing, in words the system can put in front of the person. A thrown
/// `Error` alone is silent on a Lock Screen, and "the button does nothing" is indistinguishable
/// from "the Mac is asleep" without this.
enum Trouble: Error, CustomLocalizedStringResourceConvertible {
    case noMac
    /// A decision the Mac would not take: stale, expired, already answered, or a phone not paired.
    case refused(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noMac: "Deckhand has no Mac to reach — open the app and pair it."
        case .refused(let why): "\(why)"
        }
    }
}
