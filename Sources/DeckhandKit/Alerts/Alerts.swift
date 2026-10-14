import Foundation

/// One card the Mac raised for a session, read back by something APNs cannot reach.
///
/// The daemon's `push/` decides what is worth a card — a slip nothing has answered, an agent
/// calling for the person, a list of asks gone empty — and the Lock Screen is where it goes.
/// The Mac app has no push token, so it reads the same cards off `GET /alerts` and shows each as
/// a notification. One decision, two surfaces: a folder set quiet is quiet on both.
public struct SessionAlert: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let session: String
    public let name: String
    /// `asking` or `finished`, the Lock Screen's two kinds. Only `asking` may make a noise.
    public let kind: String
    public let line: String
    public let when: Double

    public var isAsking: Bool { kind == "asking" }
}

/// What `GET /alerts` answers: every card after the cursor, and the newest id there is.
public struct SessionAlerts: Codable, Sendable {
    public var alerts: [SessionAlert] = []
    public var newest: Int = 0
}

/// Which cards are news, given what this app has already seen.
///
/// Two rules, and both are about not lying with a notification. The first look is history: cards
/// raised before the app was running are not something that just happened, so they are taken as
/// the cursor and never shown. And ids start again at 1 when the daemon does, so a newest id
/// below the one held is a restart — the cursor goes back to nothing and the next poll brings
/// everything the new daemon has raised, rather than nothing until it counts past the old one.
public struct AlertCursor: Sendable {
    /// Nil until the first poll has answered.
    public private(set) var held: Int?

    public init() {}

    /// What to ask with next.
    public var since: Int { held ?? 0 }

    /// Fold one poll in and hand back what is new.
    public mutating func absorb(_ feed: SessionAlerts) -> [SessionAlert] {
        guard let held else {
            self.held = feed.newest
            return []
        }
        guard feed.newest >= held else {
            self.held = 0
            return []
        }
        self.held = feed.newest
        return feed.alerts.filter { $0.id > held }
    }
}

public extension DeckhandClient {
    /// Every card the Mac raised after the id this app already has.
    func alerts(since: Int = 0) async throws -> SessionAlerts {
        try await get("alerts?since=\(since)")
    }
}
