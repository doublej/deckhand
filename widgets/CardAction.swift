import AppIntents
import DeckhandKit
import Foundation

/// The one thing a Lock Screen card may do to a session.
///
/// **A card may only ever make a session do less, never more.** That sentence is the whole
/// design, and it is what decides which buttons exist here. Escape can only take work away, so
/// it is on the card. Everything else is off it, by absence rather than by a check:
///
/// - **There is no Approve.** Answering a permission prompt is the keyboard route, and the root
///   CLAUDE.md's invariant is that the route is an authority choice, not a transport choice — the
///   keyboard arrives *as the person at the machine*. A finger on a Lock Screen genuinely is that
///   person, but only if that person read the question, and a card carries one line of what the
///   session said rather than the prompt it is blocked on. One tap from a phone lying face-up on
///   a table would grant a permission nobody read. The daemon has no route for it either, and
///   that is the same decision made once already at the other end.
/// - **No `compact`, no `clear`, no `exit`.** Two of them cannot be undone and the phone asks
///   before them on a screen where it can (`Control.caution`); a Lock Screen has nowhere to ask.
///   `exit` costs the session itself, which nothing on this phone can start again.
///
/// `LiveActivityIntent` rather than a plain `AppIntent`: the system performs one of these in the
/// **app's** process, so `ServerSettings.load()` reads the pairing the person typed into the app.
/// A plain `AppIntent` runs in the widget extension, which has a UserDefaults of its own and
/// would find no Mac to talk to without an App Group this project does not have.
///
/// The file lives under `widgets/` and is compiled into **both** targets (`project.yml`): the
/// widget names the intent in its `Button`, the app performs it, so each binary needs the type.
struct StopRun: LiveActivityIntent {
    static var title: LocalizedStringResource { "Stop this run" }
    static var description: IntentDescription? {
        IntentDescription("Presses Escape in this session's pane on the Mac.")
    }

    /// `.alwaysAllowed`, deliberately: Escape is the reversible control — the worst it costs is
    /// a turn that has to be asked for again — and a stop you must unlock the phone to reach is
    /// a stop you would rather do by picking the phone up.
    ///
    /// ponytail: if a stray tap turns out to be a real problem on a real phone, the upgrade is
    /// one word — `.requiresLocalDeviceAuthentication` puts Face ID in front of it.
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "Session")
    var session: String

    init() {}

    init(session: String) {
        self.session = session
    }

    func perform() async throws -> some IntentResult {
        guard let client = ServerSettings.load().client() else { throw Trouble.noMac }
        try await client.control(.cancel, of: session)
        return .result()
    }
}

/// Why a card's button did nothing, in words the system can put in front of the person. A thrown
/// `Error` alone is silent on a Lock Screen, and "the button does nothing" is indistinguishable
/// from "the Mac is asleep" without this.
enum Trouble: Error, CustomLocalizedStringResourceConvertible {
    case noMac

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noMac: "Deckhand has no Mac to reach — open the app and pair it."
        }
    }
}
