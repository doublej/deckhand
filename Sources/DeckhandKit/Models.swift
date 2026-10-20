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
    /// Claude Code in a terminal, or Codex as an app-server thread with no terminal. Optional for
    /// the same reason: a Mac that predates Codex sends no key, and that row is Claude Code.
    public var provider: Provider?
    /// Whether a client on the Mac has it open: for an OpenCode session, whether a TUI there has
    /// it as a tab. Nil from every other provider, from a Mac that cannot tell and from one that
    /// predates the field, and all of those read as open — see `isOpen`.
    public var inClient: Bool?

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

public struct Health: Codable, Hashable, Sendable {
    public let name: String
    public let version: String
    public let host: String
    /// The Mac's own address on the network. What a session's `localhost` means, from a phone
    /// that is running none of the things the session is talking about. Absent from an older Mac.
    public var lan: String?
    /// Which Mac this is, and its address off the home network. Both absent from an older Mac.
    public var id: String?, remote: String?
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
    /// The connected folder it was found in, or nil for a file the transcript named.
    public var connected: String?

    public init(path: String, name: String, kind: String, size: Int, modified: Double,
                connected: String? = nil) {
        self.path = path
        self.name = name
        self.kind = kind
        self.size = size
        self.modified = modified
        self.connected = connected
    }

    public var id: String { path }
    public var changed: Date { Date(timeIntervalSince1970: modified) }

    public enum Kind: Sendable { case image, video, audio, text }

    /// Every suffix the Mac will open, and its kind — `files.py`'s `KINDS`, copied.
    static let openable: [String: String] = Dictionary(uniqueKeysWithValues: [
        ("image", ["png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "tiff"]),
        ("video", ["mp4", "mov", "m4v"]),
        ("audio", ["mp3", "wav", "m4a", "aac", "flac", "opus", "ogg", "aiff", "caf"]),
        ("text", ["md", "txt", "log", "csv", "json", "yaml", "yml", "toml"])
    ].flatMap { kind, suffixes in suffixes.map { ($0, kind) } })

    /// A path a transcript named, as the files tab would list it before the Mac says its size.
    public init(named path: String) {
        let name = (path as NSString).lastPathComponent
        self.init(path: path, name: name,
                  kind: Self.openable[(name as NSString).pathExtension.lowercased()] ?? "text",
                  size: 0, modified: 0)
    }

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
