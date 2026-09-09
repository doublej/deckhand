import Foundation

// What a session has said, what it ran, and what you have said that it has not answered.
// Split out of `Models.swift`: the session itself is one thing, the conversation is another,
// and between them they were one file over the limit.

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
    public var queued: [Queued] = []

    public init(turns: [Turn] = [], queued: [Queued] = []) {
        self.turns = turns
        self.queued = queued
    }

    /// Tolerant, like everything else off this wire: a daemon a version behind sends no queue.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        turns = try box.decodeIfPresent([Turn].self, forKey: .turns) ?? []
        queued = try box.decodeIfPresent([Queued].self, forKey: .queued) ?? []
    }
}

/// One thing you have said that has not come back as a turn, and where it stands.
///
/// `taken` is not a nicety. A message a running turn swallows leaves the inbox without ever
/// being written to the transcript, so a queued line that simply disappeared was a message with
/// no trace anywhere — which is exactly how it looked from the phone.
public struct Queued: Codable, Hashable, Sendable, Identifiable {
    public let text: String
    public let state: String

    public var id: String { "\(state)-\(text)" }
    /// Still in the inbox. The session has not read it, and will not until its turn ends.
    public var isWaiting: Bool { state == "waiting" }

    public init(text: String, state: String = "waiting") {
        self.text = text
        self.state = state
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        text = try box.decodeIfPresent(String.self, forKey: .text) ?? ""
        state = try box.decodeIfPresent(String.self, forKey: .state) ?? "waiting"
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
