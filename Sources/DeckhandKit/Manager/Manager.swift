import Foundation

/// The manager's conversation, as the phone reads it.
///
/// It is a file on the Mac with a cursor, not a stream — see the daemon's `manager/talk.py` for
/// why. Everything here follows from that: entries carry an id, the phone asks for what comes
/// after the one it has, and `working` is the Mac saying more is on its way.
public enum ManagerRole: String, Codable, Sendable {
    /// What was said into the panel, typed or spoken.
    case person
    /// What came back. One per text block, so the panel fills in while the model is still going.
    case manager
    /// One tool the manager ran, in a line. Written by the tool, so it says what happened
    /// rather than what was asked for.
    case act
    /// Something for the phone to do. Obeyed only when newer than the cursor the panel opened
    /// with — see `ManagerDesk.obey`.
    case command
    /// The daemon speaking for itself: an error, or a conversation that had to start over.
    case note

    /// A role this build has never heard of is a note, not a thrown decode.
    ///
    /// The Mac is upgraded independently of the phone, so a daemon that grows a sixth role would
    /// otherwise take the whole conversation down on a phone that has not been rebuilt — and the
    /// text of that entry is still worth reading whatever kind it is.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ManagerRole(rawValue: raw) ?? .note
    }
}

/// Something the manager asked the phone to do. Its verbs are the daemon's `doing.ACTIONS`.
public struct ManagerCommand: Codable, Sendable, Hashable {
    public let action: String
    /// A session id for `open_session`, a pane name for `open_pane`, empty otherwise. The Mac
    /// resolves a spoken name to an id before it gets here, so this is never a name to match.
    public let target: String

    public init(action: String, target: String = "") {
        self.action = action
        self.target = target
    }
}

/// One line of the conversation.
public struct ManagerEntry: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let role: ManagerRole
    public let text: String
    /// Epoch seconds, as the Mac stamped it. `said_at` on the wire, which is where the naming
    /// comes from — `at` alone is under SwiftLint's floor for an identifier.
    public let saidAt: Double
    /// Present only on a `command`.
    public let command: ManagerCommand?

    public init(id: Int, role: ManagerRole, text: String, saidAt: Double,
                command: ManagerCommand? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.saidAt = saidAt
        self.command = command
    }

    public var date: Date { Date(timeIntervalSince1970: saidAt) }
}

/// What `GET /manager` answers: everything after the cursor, and whether more is coming.
public struct ManagerFeed: Codable, Sendable {
    public var entries: [ManagerEntry] = []
    /// The id of the last entry on the Mac — the cursor to ask with next time. Not
    /// `entries.last?.id`, which is nil on a poll that brought nothing back.
    public var newest: Int = 0
    public var working: Bool = false

    public init(entries: [ManagerEntry] = [], newest: Int = 0, working: Bool = false) {
        self.entries = entries
        self.newest = newest
        self.working = working
    }
}

/// What the Mac made of a clip spoken into the panel.
public struct ManagerHeard: Codable, Sendable {
    public var text: String?
    public var error: String?
    /// Whether it went to the manager. False when `say=false` was asked for, and false when
    /// there was nothing to send — the two are told apart by `error`.
    public var said: Bool = false
    public var entry: ManagerEntry?
}
