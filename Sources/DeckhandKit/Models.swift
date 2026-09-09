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

    public var id: String { sessionId }
    public var isBusy: Bool { status == "busy" }
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

/// One round of the conversation: what was said, by whom.
public struct Turn: Codable, Hashable, Sendable {
    public let role: String
    public let text: String
    public let timestamp: String
    /// What the session ran on its way to saying this. Empty for anything you said.
    public var tools: [Tool] = []

    public init(role: String, text: String, timestamp: String, tools: [Tool] = []) {
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.tools = tools
    }

    /// Tolerant of a daemon that predates tool traces. The phone and the Mac are updated
    /// separately — the Mac by a git pull, the phone by a rebuild — so they are routinely a
    /// version apart, and a key one of them has not heard of must not cost the whole payload.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        role = try box.decode(String.self, forKey: .role)
        text = try box.decode(String.self, forKey: .text)
        timestamp = try box.decode(String.self, forKey: .timestamp)
        tools = try box.decodeIfPresent([Tool].self, forKey: .tools) ?? []
    }

    public var isUser: Bool { role == "user" }
}

/// The conversation as the phone reads it: what has been said, and what you have said that
/// has not been picked up yet.
///
/// Two lists because they are two different things. A turn is in the session's history; a
/// queued line is in its inbox, and until it is absorbed it appears nowhere in the transcript
/// at all — which is exactly why sending something and seeing nothing happen was confusing.
public struct Rounds: Codable, Hashable, Sendable {
    public var turns: [Turn] = []
    public var queued: [String] = []

    public init(turns: [Turn] = [], queued: [String] = []) {
        self.turns = turns
        self.queued = queued
    }

    /// Tolerant, like everything else off this wire: a daemon a version behind sends no queue.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        turns = try box.decodeIfPresent([Turn].self, forKey: .turns) ?? []
        queued = try box.decodeIfPresent([String].self, forKey: .queued) ?? []
    }
}

/// One thing a session ran. Small on purpose: a dot until you ask for more.
public struct Tool: Codable, Hashable, Sendable, Identifiable {
    public let name: String
    public let detail: String
    public let succeeded: Bool
    /// The whole call and the whole answer, for when a dot and a line are not enough.
    public var call: String = ""
    public var result: String = ""

    public init(name: String, detail: String, succeeded: Bool = true,
                call: String = "", result: String = "") {
        self.name = name
        self.detail = detail
        self.succeeded = succeeded
        self.call = call
        self.result = result
    }

    /// Same tolerance as `Turn`: a daemon a version behind sends neither of the last two.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = try box.decode(String.self, forKey: .name)
        detail = try box.decode(String.self, forKey: .detail)
        succeeded = try box.decodeIfPresent(Bool.self, forKey: .succeeded) ?? true
        call = try box.decodeIfPresent(String.self, forKey: .call) ?? ""
        result = try box.decodeIfPresent(String.self, forKey: .result) ?? ""
    }

    /// Stable enough for a list that is rebuilt every few seconds from the same transcript.
    public var id: String { "\(name)\(detail)\(succeeded)" }

    /// What a tool does, which is the only thing a single dot has room to say. Reading,
    /// changing and running are worth telling apart at a glance; the exact tool is a tap away.
    public enum Kind: Sendable {
        case reading, changing, running, asking, other
    }

    public var kind: Kind {
        switch name {
        case "Read", "Grep", "Glob", "NotebookRead": .reading
        case "Edit", "Write", "NotebookEdit", "MultiEdit": .changing
        case "Bash", "BashOutput", "KillBash": .running
        case "Task", "Agent", "WebFetch", "WebSearch", "AskUserQuestion": .asking
        default: .other
        }
    }
}

/// The three things you do *to* a session rather than say to it. Each is a keystroke in its
/// pane on the Mac, exactly as it would be typed by hand.
public enum Control: String, CaseIterable, Sendable {
    /// Escape: stop what it is doing now.
    case cancel
    /// `/compact`: fold the conversation so far into a summary and carry on.
    case compact
    /// `/clear`: throw the conversation away. There is no undo, so the phone asks first.
    case clear

    public var label: String {
        switch self {
        case .cancel: "Stop this run"
        case .compact: "Compact the conversation"
        case .clear: "Clear the conversation"
        }
    }

    public var symbol: String {
        switch self {
        case .cancel: "stop.circle"
        case .compact: "arrow.down.right.and.arrow.up.left"
        case .clear: "eraser"
        }
    }

    /// True for the one that cannot be undone.
    public var asksFirst: Bool { self == .clear }
}

/// What became of a line of text handed to a session.
public struct Delivery: Codable, Hashable, Sendable {
    public let delivered: Bool
    public let deliveredBy: String?
    public let deliveryError: String?
}

/// What the Mac wrote to disk for an uploaded clip. `transcript` stays nil until phase two.
public struct UploadReceipt: Codable, Hashable, Sendable {
    public let path: String
    public let bytes: Int
    public let receivedAt: Double
    public let transcript: String?
    public let transcriptError: String?
    /// Whether the text reached the session itself, which way it went in, and why not when
    /// it did not.
    public let delivered: Bool
    public let deliveredBy: String?
    public let deliveryError: String?
}

public struct Health: Codable, Hashable, Sendable {
    public let name: String
    public let version: String
    public let host: String
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

    public enum Kind: Sendable { case image, video, text }

    public var sort: Kind {
        switch kind {
        case "image": .image
        case "video": .video
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
}

public extension String {
    /// Runs of whitespace flattened to single spaces. The daemon does this to anything it
    /// types or sends, so it is the only form in which what was said and what came back can
    /// be compared.
    var collapsed: String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
