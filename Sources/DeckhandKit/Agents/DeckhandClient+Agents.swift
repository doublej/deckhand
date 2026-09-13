import Foundation

extension DeckhandClient {
    /// Every subagent a session has started, newest first.
    ///
    /// A daemon that has never heard of this route answers 404, which `send` reads as `notLive` —
    /// so a caller treats a throw here as "none", never as the session having gone. The phone and
    /// the Mac update separately, and a screen must not empty itself over a version gap.
    public func agents(of sessionId: String) async throws -> [Agent] {
        let body: [String: [Agent]] = try await get("sessions/\(sessionId)/agents")
        return body["agents"] ?? []
    }

    /// One subagent's own conversation, paged exactly as a session's is.
    ///
    /// No `queued`, and no route would give it one: a subagent has no inbox socket and no name
    /// anything could address. Reading is the whole of what it offers.
    public func turns(ofAgent agentId: String, in sessionId: String,
                      limit: Int = 8, before: Int = 0) async throws -> Rounds {
        try await get("sessions/\(sessionId)/agents/\(agentId)/turns?limit=\(limit)&before=\(before)")
    }
}
