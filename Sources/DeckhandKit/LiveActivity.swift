// `Foundation` above the guard: `CardLink` at the foot of this file is the one thing here that
// is only characters, and it has to compile on the Mac where `just test` runs.
import Foundation

#if os(iOS)
import ActivityKit

/// What one session's Lock Screen card shows, and the shape the daemon has to produce on the
/// other side of APNs.
///
/// Every field is a plain value on purpose. This struct is decoded by iOS from JSON the daemon
/// composed in Python, so there is no Swift on the sending side to keep in step — the wire
/// format *is* the contract. `when` is Unix seconds rather than a `Date` for the same reason:
/// Foundation would encode a `Date` as its own reference-date offset, which is a trap for
/// anything not written in Swift.
///
/// **One card is one session, not the Mac.** It was a count once — "5 waiting" — and a count is
/// the one thing a person cannot act on: five finished turns and five blocked questions drew the
/// same card. A card about one session can say which one, what it asked, and whether it needs an
/// answer, and the number of them on the Lock Screen is the count, drawn by iOS for free.
public struct Deck: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Why this card is on screen. The whole of the interruption policy: `asking` may raise a
        /// card and may make a noise, `finished` may only ever update one that is already there.
        ///
        /// Decoded leniently — an unknown word is `finished`, the quiet one, so a daemon that
        /// learns a new kind can never make an older phone louder than it was built to be.
        public var kind: Kind
        /// The first thing it said, or what it asked for. Never empty: a card with nothing to
        /// read is the card this design exists to stop drawing.
        public var line: String
        /// Unix seconds. The view makes it tick by itself so a glance says how stale this is.
        public var when: Double
        /// A yes-or-no slip this card can answer from the Lock Screen, and the words on its Yes
        /// and No buttons — all three or none. The daemon only sends them for a confirm slip, and then
        /// `line` is that slip's question, so a Yes is never pressed under any other sentence.
        /// Optional, so a card from an older Mac decodes with no buttons rather than not at all.
        public var slip: String?
        public var accept: String?
        public var decline: String?
        /// The slip's page hash when the slip is a decision: the card's Yes is then signed with
        /// the phone's key over exactly this version of the page. Nil for anything else, and for
        /// a Mac older than decisions, whose cards answer the way they always did.
        public var hash: String?

        public init(kind: Kind, line: String, when: Double,
                    slip: String? = nil, accept: String? = nil, decline: String? = nil,
                    hash: String? = nil) {
            self.kind = kind
            self.line = line
            self.when = when
            self.slip = slip
            self.accept = accept
            self.decline = decline
            self.hash = hash
        }

        public var moment: Date { Date(timeIntervalSince1970: when) }
    }

    /// Why a card exists, in the order a person cares: something wants you, or something is done.
    public enum Kind: String, Codable, Hashable, CaseIterable {
        /// A slip nobody has answered, or an agent that called for you in its own words.
        case asking
        /// This session has cleared everything on your list for it. Quiet by design — a single
        /// ask being ticked off is 12 an hour and is not news; the list going empty is.
        case finished

        /// Unknown decodes to the quiet one. The `ManagerRole` precedent: a word this build has
        /// never heard of must never be the loud interpretation.
        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .finished
        }
    }

    /// The session this card is about. Fixed for the card's whole life, which is why it is an
    /// attribute rather than state: a card never changes which session it speaks for.
    public var session: String
    /// Byte-identical to the name on the rail. `DotGlyph.forName` is FNV-1a over exactly this
    /// string, so one character's difference gives the session a different face in two places.
    public var name: String
    /// Which Mac this is, so a second one is never mistaken for the first.
    public var mac: String

    public init(session: String, name: String, mac: String) {
        self.session = session
        self.name = name
        self.mac = mac
    }
}

public extension Deck {
    /// Where a tap on this card goes. `CardLink` below holds the shape; this is the spelling the
    /// widget reaches for, because a card already has its own session in hand.
    var cardLink: URL? { CardLink.toSession(session) }
}
#endif

/// Where a tap on the card goes.
///
/// The widget hands this to `.widgetURL` and the app reads it back in `onOpenURL`, so the
/// spelling is written once. It was `deckhand://waiting` and nothing at all answered it: no
/// `CFBundleURLTypes`, no `onOpenURL`, so every tap opened the app on the sessions list whichever
/// card was pressed. A card is about one session and now says which in the URL.
///
/// `sessions` plural, matching the daemon's own `/sessions/{id}` — there is no second word for
/// this in the product and this is not the place to invent one.
///
/// **Outside the `#if os(iOS)` above, deliberately.** `Deck` needs ActivityKit and so cannot
/// exist on the Mac; a URL is only characters. Keeping the shape out here is what lets
/// `just test` hold both ends of it down without a simulator, which is the same argument every
/// other pure thing in this module is here for.
public enum CardLink {
    public static let scheme = "deckhand"
    private static let sessions = "sessions"

    /// Optional rather than force-unwrapped: a session id is a UUID today, but a `!` here would
    /// be a crash on the Lock Screen the one time that stops being true.
    public static func toSession(_ session: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = sessions
        parts.path = "/\(session)"
        return parts.url
    }

    /// The session a `deckhand://` URL names, or nil for anything else the system hands over.
    ///
    /// The first path component rather than `lastPathComponent`, which answers `"/"` — a
    /// perfectly non-empty string — for `deckhand://sessions/`, and would have the rail look for
    /// a session called that. `pathComponents` also hands back what the escaping put in.
    public static func session(openedBy url: URL) -> String? {
        guard url.scheme == scheme, url.host() == sessions else { return nil }
        return url.pathComponents.dropFirst().first
    }
}
