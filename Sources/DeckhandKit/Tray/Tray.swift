import Foundation

/// What a waiting slip asks, read off its page by the Mac, so the tray can ask it in place.
///
/// The page is still the whole truth of a slip; this is the four kinds `slip.py` writes, which say
/// in their markup exactly what they ask. Anything the Mac could not read is `page`, opened as it
/// always was — never guessed at, because a wrong guess sends an answer the page would not have.
public struct SlipAsk: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case confirm, pick, text, aloud, page

        /// Unknown is `page`: a kind this build has never heard of is opened, never answered.
        public init(from decoder: any Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .page
        }
    }

    public let kind: Kind
    /// A confirm's two buttons, in the page's own words.
    public var accept: String?
    public var decline: String?
    /// A pick's rows, and whether the page also takes an answer typed in.
    public var options: [String]?
    public var other: Bool?
    /// A text field's label.
    public var label: String?

    public init(kind: Kind, accept: String? = nil, decline: String? = nil,
                options: [String]? = nil, other: Bool? = nil, label: String? = nil) {
        self.kind = kind
        self.accept = accept
        self.decline = decline
        self.options = options
        self.other = other
        self.label = label
    }

    /// The JSON the page itself responds with: `{"answer": …}`, for all three kinds drawn here.
    public static func answer(_ value: Bool) -> String { #"{"answer":\#(value)}"# }

    public static func answer(_ words: String) -> String {
        guard let data = try? JSONEncoder().encode(["answer": words]),
              let json = String(bytes: data, encoding: .utf8) else { return #"{"answer":""}"# }
        return json
    }
}

/// One slip nobody has answered, with what it asks.
public struct TraySlip: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let modified: Double
    public var shared: Bool?
    public let ask: SlipAsk

    /// The listing's own row, for the viewer that opens a page.
    public var artifact: Artifact {
        Artifact(id: id, title: title, modified: modified, answered: false, shared: shared ?? false)
    }
}

/// One session that needs the person: its waiting slips, and the line it called for you with.
public struct TraySession: Codable, Hashable, Identifiable, Sendable {
    public let session: String
    public let name: String
    public var machine: String?
    public var status: String?
    public var provider: String?
    /// What it is waiting on you for, in its own words. Empty where it never said.
    public var waiting: String?
    public var slips: [TraySlip]

    public var id: String { session }
}

/// One thing that happened to a session that needed you.
public struct TrayUpdate: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case answered, called, blocked, done, finished, other
    }

    public let id: Int
    /// The wire word. Read through `kind`, so a word this build has never heard is `other`.
    public let type: String
    public let session: String
    public let name: String
    public var machine: String?
    public let when: Double
    /// `answered`: which slip, its question, and the answer in the words on its button.
    public var slip: String?
    public var title: String?
    public var answer: String?
    /// `called` and `blocked`: what it asked you for.
    public var line: String?
    /// `done`: the ask that was finished. `finished`: the whole list, now clear.
    public var ask: String?
    public var asks: [String]?

    public var kind: Kind { Kind(rawValue: type) ?? .other }
    public var moment: Date { Date(timeIntervalSince1970: when) }

    enum CodingKeys: String, CodingKey {
        case id, type = "kind", session, name, machine, when, slip, title, answer, line, ask, asks
    }
}

/// What `GET /tray` answers.
public struct TrayFeed: Codable, Sendable {
    public var open: [TraySession] = []
    public var updates: [TrayUpdate] = []
    public var newest: Int = 0

    public init(open: [TraySession] = [], updates: [TrayUpdate] = [], newest: Int = 0) {
        self.open = open
        self.updates = updates
        self.newest = newest
    }
}

public extension DeckhandClient {
    /// Everything open on every machine, and every update after the id this phone already has.
    func tray(since: Int = 0) async throws -> TrayFeed {
        try await get("tray?since=\(since)")
    }
}
