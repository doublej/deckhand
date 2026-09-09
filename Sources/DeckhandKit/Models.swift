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
}

/// One round of the conversation: what was said, by whom.
public struct Turn: Codable, Hashable, Sendable {
    public let role: String
    public let text: String
    public let timestamp: String

    public var isUser: Bool { role == "user" }
}

/// What the Mac wrote to disk for an uploaded clip. `transcript` stays nil until phase two.
public struct UploadReceipt: Codable, Hashable, Sendable {
    public let path: String
    public let bytes: Int
    public let receivedAt: Double
    public let transcript: String?
}

public struct Health: Codable, Hashable, Sendable {
    public let name: String
    public let version: String
    public let host: String
}

public enum DeckhandError: Error, Equatable, Sendable {
    case unauthorized
    case notLive
    case http(Int, String)
    case badResponse
}
