import Foundation

/// The iTerm pane a session is running in. Absent when iTerm cannot be reached.
public struct Pane: Codable, Hashable, Sendable {
    public let itermSessionId: String
    public let windowId: String
    public let tabId: String
    public let title: String
}

/// One live Claude Code session on the Mac.
public struct Session: Codable, Hashable, Identifiable, Sendable {
    public let sessionId: String
    public let pid: Int
    public let name: String
    public let cwd: String
    public let folder: String
    public let status: String
    public let updatedAt: Double
    public let tty: String
    public let pane: Pane?
    /// How full its context window is. Absent from a daemon that predates it — the synthesised
    /// decoder reads an optional with `decodeIfPresent`, so a missing key is simply nil.
    public var context: ContextWindow?
    /// How far this project has got with the slips it put on the phone: how many nobody has
    /// answered yet, and how many have an answer beside them.
    ///
    /// Optional for exactly the reason `context` is, and not an `Int = 0`: the synthesised
    /// decoder only tolerates a missing key for an optional, so a Mac that predates these is a
    /// session with no slips rather than a listing that will not decode at all.
    public var artifactsWaiting: Int?
    public var artifactsAnswered: Int?
    /// The model that answered its last request, written the way Claude Code writes it down
    /// (`claude-sonnet-5`), and the reasoning effort that request ran at. Both come off the same
    /// transcript entry `context` does, and both are optional for the same reason it is.
    public var model: String?
    public var effort: String?
    /// Which machine it is running on, as the Mac's registry names it — `m2`, `ubuntu`.
    ///
    /// Optional for the reason every optional above it is: the synthesised decoder tolerates a
    /// missing key only on an optional, so a non-optional here would make an older Mac's whole
    /// listing fail to decode rather than simply say nothing about machines.
    public var machine: String?

    public var id: String { sessionId }
    public var isBusy: Bool { status == "busy" }
    /// Those two counts, in the form every screen wants them, so that nowhere has to spell out
    /// what a Mac with nothing to say about slips means.
    public var waitingPages: Int { artifactsWaiting ?? 0 }
    public var answeredPages: Int { artifactsAnswered ?? 0 }
    public var pages: Int { waitingPages + answeredPages }
    public var lastActive: Date { Date(timeIntervalSince1970: updatedAt) }

    /// Identity is the session, not its current state. Every refresh brings a new `updatedAt`
    /// and a new `status`; if those counted, every list row would change identity every few
    /// seconds and a tap in flight would land on nothing.
    public static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.sessionId == rhs.sessionId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sessionId)
    }
}

/// How much of a session's context window is gone.
///
/// Not `Context`: inside a `UIViewRepresentable` that name is already a typealias of SwiftUI's
/// own, and a public type called `Context` in a module imported beside SwiftUI silently breaks
/// the conformance of anything that spells its `makeUIView(context:)` the documented way.
///
/// The limit is the one Claude Code is actually configured to compact at on that Mac
/// (`autoCompactWindow`), not the model's own ceiling: what matters is when *this* session
/// will fold itself into a summary, which is a setting rather than a fact about the model.
public struct ContextWindow: Codable, Hashable, Sendable {
    public let used: Int
    public let limit: Int

    public init(used: Int, limit: Int) {
        self.used = used
        self.limit = limit
    }

    public var share: Double {
        limit > 0 ? min(1, Double(used) / Double(limit)) : 0
    }

    /// "319k of 450k" — thousands, because nobody reads the last three digits of either.
    public var line: String {
        "\(Self.thousands(used)) of \(Self.thousands(limit))"
    }

    private static func thousands(_ count: Int) -> String {
        count < 1000 ? "\(count)" : "\(count / 1000)k"
    }

    /// Three bands, because the only decision this drives is whether to do something about it.
    public enum Pressure: Sendable { case easy, tight, full }

    public var pressure: Pressure {
        switch share {
        case ..<0.75: .easy
        case ..<0.9: .tight
        default: .full
        }
    }
}

/// What became of a line of text handed to a session.
public struct Delivery: Codable, Hashable, Sendable {
    public let delivered: Bool
    public let deliveredBy: String?
    public let deliveryError: String?
    /// What the filters on the Mac wanted said about the words on their way in: what was
    /// swapped, what was looked up. Empty from a daemon that predates filtering.
    public var notes: [String] = []
    /// The filter that refused to let the words through, when one did.
    public var stoppedBy: String?

    /// Whether the words actually reached the session. `delivered` alone is not that question:
    /// a filter stopping something is not a delivery failure, it is a deliberate no, and every
    /// screen here has to tell the person which of the two happened.
    public var went: Bool { delivered && stoppedBy == nil }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        delivered = try box.decodeIfPresent(Bool.self, forKey: .delivered) ?? false
        deliveredBy = try box.decodeIfPresent(String.self, forKey: .deliveredBy)
        deliveryError = try box.decodeIfPresent(String.self, forKey: .deliveryError)
        notes = try box.decodeIfPresent([String].self, forKey: .notes) ?? []
        stoppedBy = try box.decodeIfPresent(String.self, forKey: .stoppedBy)
    }
}

/// What the Mac wrote to disk for an uploaded clip. `transcript` stays nil until phase two.
public struct UploadReceipt: Codable, Hashable, Sendable {
    public let path: String
    public let bytes: Int
    public let receivedAt: Double
    public let transcript: String?
    public let transcriptError: String?
    /// The words after the chain has run over them, and nil when it changed nothing. Only on a
    /// clip that asked not to be delivered — there is nothing to prepare for words already gone.
    public var prepared: String?
    /// Whether the text reached the session itself, which way it went in, and why not when
    /// it did not.
    public let delivered: Bool
    public let deliveredBy: String?
    public let deliveryError: String?
    /// The filters' own two answers, exactly as on `Delivery`: what they wanted to say, and
    /// which of them refused. Both absent from a daemon that predates filtering.
    public var notes: [String] = []
    public var stoppedBy: String?
    /// What each stage on the Mac cost, in milliseconds and in the order they ran. Empty from a
    /// daemon that predates the measurement, which is the only state this has to tolerate.
    public var timings: [Stage] = []
    /// The recogniser's own words, before utt's own pipeline touched them.
    ///
    /// **This does not exist yet.** utt's jobs lane answers with `text`, `error` and
    /// `finishedAt`; `raw` is in scope in its `ProcessedTranscript` and dropped at that
    /// boundary. Nothing here stubs it: the daemon passes through whatever utt sends, and the
    /// day utt sends this the card starts showing what its cleanup rewrote. Until then it is
    /// nil and nothing appears.
    public var raw: String?
    /// The utt stages that actually *changed* the words — not the ones that ran.
    ///
    /// It is this and not `raw != text` that says a rewrite happened, exactly as utt's own
    /// `ProcessedTranscript.changed` does: the pipeline trims, and whitespace is not something
    /// to show a person a before-and-after of.
    public var uttStages: [String] = []
    /// Set when utt's cleanup was on and did not run, with the reason it gives.
    public var cleanupSkipped: String?

    public var went: Bool { delivered && stoppedBy == nil }

    /// What the Mac said the whole request took. The upload span with this taken out of it is
    /// the network, which is why nothing measures the network twice.
    public var macTotal: Double? { timings.first { $0.name == "total" }?.took }

    /// True when utt's own pipeline rewrote the words on the way here, and there is therefore a
    /// before and an after worth showing. False on every Mac until utt starts sending `raw`.
    public var uttRewrote: Bool { raw != nil && !uttStages.isEmpty }

    /// The words to put in front of the person: what the chain made of them, or what utt heard
    /// when the chain left them alone.
    ///
    /// `transcript` keeps meaning what was heard, which is why this is a second field and not a
    /// rewrite of the first. The card has to show this one: a card reading "deck hand" while the
    /// session is about to be handed "deckhand" lies about the very thing it exists to confirm.
    public var words: String? { prepared ?? transcript }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        path = try box.decodeIfPresent(String.self, forKey: .path) ?? ""
        bytes = try box.decodeIfPresent(Int.self, forKey: .bytes) ?? 0
        receivedAt = try box.decodeIfPresent(Double.self, forKey: .receivedAt) ?? 0
        transcript = try box.decodeIfPresent(String.self, forKey: .transcript)
        transcriptError = try box.decodeIfPresent(String.self, forKey: .transcriptError)
        prepared = try box.decodeIfPresent(String.self, forKey: .prepared)
        delivered = try box.decodeIfPresent(Bool.self, forKey: .delivered) ?? false
        deliveredBy = try box.decodeIfPresent(String.self, forKey: .deliveredBy)
        deliveryError = try box.decodeIfPresent(String.self, forKey: .deliveryError)
        notes = try box.decodeIfPresent([String].self, forKey: .notes) ?? []
        stoppedBy = try box.decodeIfPresent(String.self, forKey: .stoppedBy)
        timings = try box.decodeIfPresent([Stage].self, forKey: .timings) ?? []
        raw = try box.decodeIfPresent(String.self, forKey: .raw)
        uttStages = try box.decodeIfPresent([String].self, forKey: .uttStages) ?? []
        cleanupSkipped = try box.decodeIfPresent(String.self, forKey: .cleanupSkipped)
    }

    /// Spelled out because one key has to be: utt writes `stages`, and this type already has
    /// stages of its own under `timings`. The rest are the synthesised names — `.convertFromSnakeCase`
    /// has already turned `transcript_error` into `transcriptError` before any of them is looked up.
    enum CodingKeys: String, CodingKey {
        case path, bytes, receivedAt, transcript, transcriptError, prepared
        case delivered, deliveredBy, deliveryError, notes, stoppedBy
        case timings, raw, cleanupSkipped
        case uttStages = "stages"
    }
}

public struct Health: Codable, Hashable, Sendable {
    public let name: String
    public let version: String
    public let host: String
    /// The Mac's own address on the network. What a session's `localhost` means, from a phone
    /// that is running none of the things the session is talking about. Absent from an older Mac.
    public var lan: String?
    /// "ok", or why the Mac cannot see iTerm panes right now.
    public let iterm: String?
}

/// A file this session touched that you could actually open: a shot it took, a note it wrote.
public struct Asset: Codable, Hashable, Sendable, Identifiable {
    public let path: String
    public let name: String
    public let kind: String
    public let size: Int
    public let modified: Double

    public init(path: String, name: String, kind: String, size: Int, modified: Double) {
        self.path = path
        self.name = name
        self.kind = kind
        self.size = size
        self.modified = modified
    }

    public var id: String { path }
    public var changed: Date { Date(timeIntervalSince1970: modified) }

    public enum Kind: Sendable { case image, video, audio, text }

    public var sort: Kind {
        switch kind {
        case "image": .image
        case "video": .video
        case "audio": .audio
        default: .text
        }
    }

    /// The folder it sits in, which is most of what tells two `report.md`s apart.
    public var folder: String {
        (path as NSString).deletingLastPathComponent
    }
}

public enum DeckhandError: Error, Equatable, Sendable {
    case unauthorized
    case notLive
    case http(Int, String)
    case badResponse

    /// The sentence the Mac refused with, when it sent one.
    ///
    /// FastAPI answers every rejection as `{"detail": …}`, and the detail is the only half a
    /// person can do anything about: "no such filter: translate" rather than "Mac said 400:
    /// {"detail"…". Nil for a body that is not one — a validation error's detail is a list of
    /// its own, and an HTML error page is not a sentence either.
    public var detail: String? {
        guard case .http(_, let body) = self else { return nil }
        struct Refusal: Decodable { let detail: String }
        return (try? JSONDecoder().decode(Refusal.self, from: Data(body.utf8)))?.detail
    }
}

public extension String {
    /// Runs of whitespace flattened to single spaces. The daemon does this to anything it
    /// types or sends, so it is the only form in which what was said and what came back can
    /// be compared.
    var collapsed: String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
