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

/// What a session has been doing since you last spoke to it.
public struct Summary: Codable, Hashable, Sendable {
    public let summary: String?
    /// The first line of it: what you need to know or do, short enough for a list row.
    public var headline: String?
    public let error: String?

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        summary = try box.decodeIfPresent(String.self, forKey: .summary)
        headline = try box.decodeIfPresent(String.self, forKey: .headline)
        error = try box.decodeIfPresent(String.self, forKey: .error)
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
