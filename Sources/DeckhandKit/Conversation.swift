import Foundation

// What a session has said, what it ran, and what you have said that it has not answered.
// Split out of `Models.swift`: the session itself is one thing, the conversation is another,
// and between them they were one file over the limit.

/// One round of the conversation: what was said, by whom.
public struct Turn: Codable, Hashable, Sendable {
    public let role: String
    public let text: String
    public let timestamp: String
    /// Who wrote it, when it was not the person: a subagent by name, another session, or the
    /// harness saying a background run has stopped. Empty is the person themselves. Every one of
    /// these arrives with `role` "user", so without this the phone puts a subagent's report in
    /// JJ's mouth — which is the one attribution that has to be right.
    public var writtenBy: String = ""
    /// What the session ran on its way to saying this. Empty for anything you said.
    public var tools: [Tool] = []
    /// What it thought on the way there, in order, and empty for anything you said. Carried with
    /// the turn rather than fetched on demand: a page of them measured 18 KB against tool results
    /// already capped at four thousand characters each, and travelling together is what makes a
    /// run still in flight show its thinking as it happens — the phone re-reads this page every
    /// few seconds and a session mid-turn has thoughts and no words yet.
    public var thoughts: [String] = []

    public init(role: String, text: String, timestamp: String, writtenBy: String = "",
                tools: [Tool] = [], thoughts: [String] = []) {
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.writtenBy = writtenBy
        self.tools = tools
        self.thoughts = thoughts
    }

    /// Tolerant of a daemon that predates tool traces. The phone and the Mac are updated
    /// separately — the Mac by a git pull, the phone by a rebuild — so they are routinely a
    /// version apart, and a key one of them has not heard of must not cost the whole payload.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        role = try box.decode(String.self, forKey: .role)
        text = try box.decode(String.self, forKey: .text)
        timestamp = try box.decode(String.self, forKey: .timestamp)
        writtenBy = try box.decodeIfPresent(String.self, forKey: .writtenBy) ?? ""
        tools = try box.decodeIfPresent([Tool].self, forKey: .tools) ?? []
        thoughts = try box.decodeIfPresent([String].self, forKey: .thoughts) ?? []
    }

    /// Yours, and nobody else's. A turn somebody else wrote is a `user` entry too, so the role
    /// alone is not the question.
    public var isUser: Bool { role == "user" && writtenBy.isEmpty }

    /// The name to put over it. `theirs` is what the other side of this particular screen is
    /// called — a session is Claude, the manager panel is the manager — and it is used only when
    /// nobody else signed the turn.
    public func speaker(theirs: String = "CLAUDE") -> String {
        writtenBy.isEmpty ? (isUser ? "YOU" : theirs) : writtenBy.uppercased()
    }

    /// When it was said, or nil where nothing said when.
    ///
    /// Nil is a real answer and not an error: the manager panel builds its turns by hand with no
    /// stamp at all, and a turn still in flight is sent with an empty one because it has not
    /// finished happening. Both draw no time rather than a wrong one.
    ///
    /// Two parses because the Mac hands over whatever Claude Code wrote in the transcript, and
    /// that is ISO 8601 with fractional seconds — a spelling the plain reader rejects outright
    /// rather than rounding. The second is the fallback for a stamp without them, so neither
    /// spelling is the one that silently loses the time.
    ///
    /// `Date.ISO8601FormatStyle` and not `ISO8601DateFormatter`: the formatter is a class that
    /// does not conform to `Sendable`, so holding one in a `static let` is a compile error under
    /// this package's strict concurrency. The style is a value and costs nothing to make.
    public var moment: Date? {
        guard !timestamp.isEmpty else { return nil }
        let precise = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let exact = try? precise.parse(timestamp) { return exact }
        return try? Date.ISO8601FormatStyle().parse(timestamp)
    }

    /// The time to put on the card. Empty where ``moment`` is nil, so the view asks one question.
    ///
    /// The clock rather than "2m ago": a transcript is a record of when things happened, and a
    /// relative age on a row that never moves is a number that goes stale while you read it.
    /// The date comes too once the turn is not from today — a bare `13:03` on a turn from
    /// Tuesday is the one reading that is actively wrong.
    public var clock: String {
        guard let moment else { return "" }
        return Calendar.current.isDateInToday(moment)
            ? moment.formatted(date: .omitted, time: .shortened)
            : moment.formatted(date: .abbreviated, time: .shortened)
    }
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
    /// Whether the Mac has older turns than these. The phone keeps no transcript of its own —
    /// the Mac holds the file and does the parsing — so this is how a screen reading backwards
    /// knows when it has reached the beginning rather than guessing from a short page.
    public var more = false

    public init(turns: [Turn] = [], queued: [Queued] = [], more: Bool = false) {
        self.turns = turns
        self.queued = queued
        self.more = more
    }

    /// Tolerant, like everything else off this wire: a daemon a version behind sends no queue,
    /// and one older still says nothing about older pages — which reads as "there are none",
    /// and leaves such a Mac working exactly as it did.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        turns = try box.decodeIfPresent([Turn].self, forKey: .turns) ?? []
        queued = try box.decodeIfPresent([Queued].self, forKey: .queued) ?? []
        more = try box.decodeIfPresent(Bool.self, forKey: .more) ?? false
    }
}

/// One thing you have said that is still sitting in the session's inbox, unread.
///
/// Only that. A message the session has already taken is not here — it is a turn, in the place
/// it arrived, because Claude Code files a mid-run message as an attachment rather than as a
/// user entry and the Mac reads those now. Keeping a copy here as well is what put three
/// answered prompts at the foot of the transcript looking like three nobody had got to.
public struct Queued: Codable, Hashable, Sendable, Identifiable {
    public let text: String

    public var id: String { text }

    public init(text: String) {
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        text = try box.decodeIfPresent(String.self, forKey: .text) ?? ""
    }
}

/// One thing a session ran. Small on purpose: a dot until you ask for more.
public struct Tool: Codable, Hashable, Sendable, Identifiable {
    public let name: String
    public let detail: String
    public let succeeded: Bool
    /// Claude Code's own id for this call, and the join to a subagent: an `Agent` row carries the
    /// same string as its `toolUseId`. Empty from a daemon that predates it, which is why nothing
    /// is keyed on it being there.
    public var toolId: String = ""
    /// The whole call and the whole answer, for when a dot and a line are not enough.
    public var call: String = ""
    public var result: String = ""

    public init(name: String, detail: String, succeeded: Bool = true,
                call: String = "", result: String = "", toolId: String = "") {
        self.name = name
        self.detail = detail
        self.succeeded = succeeded
        self.call = call
        self.result = result
        self.toolId = toolId
    }

    /// Same tolerance as `Turn`: a daemon a version behind sends neither of the last two.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = try box.decode(String.self, forKey: .name)
        detail = try box.decode(String.self, forKey: .detail)
        succeeded = try box.decodeIfPresent(Bool.self, forKey: .succeeded) ?? true
        call = try box.decodeIfPresent(String.self, forKey: .call) ?? ""
        toolId = try box.decodeIfPresent(String.self, forKey: .toolId) ?? ""
        result = try box.decodeIfPresent(String.self, forKey: .result) ?? ""
    }

    /// Claude Code's own id where the Mac sent one, and otherwise what it always was: stable
    /// enough for a list rebuilt every few seconds from the same transcript.
    public var id: String { toolId.isEmpty ? "\(name)\(detail)\(succeeded)" : toolId }

    /// A subagent, rather than something this session ran itself. `Task` is the older spelling
    /// and still appears in transcripts written before it changed; `subagent` is OpenCode's.
    public var isAgent: Bool { name == "Agent" || name == "Task" || name == "subagent" }

    /// What a tool does, which is the only thing a single dot has room to say. Reading,
    /// changing and running are worth telling apart at a glance; the exact tool is a tap away.
    public enum Kind: Sendable, Equatable {
        case reading, changing, running, asking, other
    }

    /// Claude Code's tool names, then OpenCode's own lowercase ones, which the Mac passes through
    /// as OpenCode wrote them rather than translating — the expanded dot shows the real name.
    public var kind: Kind {
        switch name {
        case "Read", "Grep", "Glob", "NotebookRead", "read", "grep", "glob", "list": .reading
        case "Edit", "Write", "NotebookEdit", "MultiEdit", "edit", "write", "apply_patch":
            .changing
        case "Bash", "BashOutput", "KillBash", "shell": .running
        case "Task", "Agent", "WebFetch", "WebSearch", "AskUserQuestion",
             "subagent", "webfetch", "websearch", "question": .asking
        default: .other
        }
    }
}

/// One CLAUDE.md a session in a folder is loaded with, ready to draw as a row of a tree.
///
/// Not a file the session touched — that is `Asset`, and the transcript bounds it. This is the
/// standing instruction it started with, which is the other half of "why did it do that": a rule
/// three folders up never appears in a transcript and is running all the same.
///
/// The connector arrives drawn. The Mac already knows which branches are still open at every
/// level, and a phone re-deriving that from a depth number is a second implementation of one
/// thing — so the tree is printed in a monospaced font exactly as the Mac laid it out, which is
/// also what makes it the same picture `atlas tree` draws.
public struct Doc: Codable, Hashable, Sendable, Identifiable {
    public let path: String
    /// The folder it speaks for, not the file name: every row is a `CLAUDE.md`, so the name
    /// eighty times over says nothing.
    public let label: String
    /// `ancestor`, `root`, `project`, `descendant`, `glossary` or `rule` — atlas's own words.
    public let kind: String
    public let prefix: String
    public let size: Int
    public let tokens: Int

    public init(path: String, label: String, kind: String, prefix: String,
                size: Int, tokens: Int) {
        self.path = path
        self.label = label
        self.kind = kind
        self.prefix = prefix
        self.size = size
        self.tokens = tokens
    }

    public var id: String { path }

    /// The tree opens a document the same way the files list opens a file, so it hands back the
    /// same thing every screen downstream already knows how to read.
    public var asset: Asset {
        Asset(path: path, name: (path as NSString).lastPathComponent,
              kind: "text", size: size, modified: 0)
    }
}

/// A folder's whole context tree, and what it costs to load.
///
/// `ContextDocs` and not `Context`: inside a `UIViewRepresentable`, `Context` is already a
/// typealias for `UIViewRepresentableContext<Self>`, so a public `Context` in this module
/// silently breaks the conformance of every representable in the app and the errors all name the
/// representable rather than the clash. It cost a build to relearn. See `ContextWindow`, which is
/// spelled out for exactly the same reason.
public struct ContextDocs: Codable, Sendable {
    public let documents: [Doc]
    public let tokens: Int

    public init(documents: [Doc] = [], tokens: Int = 0) {
        self.documents = documents
        self.tokens = tokens
    }
}

public extension DeckhandClient {
    /// The CLAUDE.md tree a session in this folder is loaded with.
    func context(of sessionId: String) async throws -> ContextDocs {
        try await get("sessions/\(sessionId)/context")
    }
}
