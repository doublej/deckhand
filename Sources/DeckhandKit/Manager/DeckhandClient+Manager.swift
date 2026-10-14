import Foundation

/// The manager's four calls. The same type as `DeckhandClient`, in another file, for the reason
/// `DeckhandClient+Clips.swift` gives: that file is on its length gate and this folder has room.
public extension DeckhandClient {
    /// Everything said after the id this phone already has. `since: 0` is the whole conversation.
    ///
    /// The cursor is the whole protocol. A phone that was in a pocket for an hour catches up in
    /// one call, and a phone polling every second carries almost nothing back.
    ///
    /// `watching: false` is a poll with no panel on screen — the Mac app noticing replies from
    /// its menu bar. Every other poll tells the Mac the panel is open, which stops it pushing.
    func manager(since: Int = 0, watching: Bool = true) async throws -> ManagerFeed {
        try await get("manager?since=\(since)" + (watching ? "" : "&watching=false"))
    }

    /// Say something to the manager. Answers with the entry it was written as, not with the
    /// reply: the Mac never makes the phone wait for a model, and the reply arrives by poll.
    @discardableResult
    func askManager(_ text: String) async throws -> ManagerEntry {
        struct Asked: Encodable { let text: String }
        struct Answer: Decodable { let entry: ManagerEntry }
        var req = request(.post, "manager/say")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONEncoder().encode(Asked(text: text))
        let answer: Answer = try decode(try await send(req, body: body))
        return answer.entry
    }

    /// A clip spoken into the panel. `say: false` transcribes only, for the review card.
    func upload(clip: URL, say: Bool = true) async throws -> ManagerHeard {
        let boundary = "deckhand.\(UUID().uuidString)"
        var req = request(.post, "manager/audio?say=\(say)")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // The Mac transcribes before answering, and utt's first request loads the model. The
        // same 200 seconds a session's clip gets, and for the same reason.
        req.timeoutInterval = 200
        return try decode(try await send(req, body: try multipart(boundary: boundary, clip: clip)))
    }

    /// The panel went off screen, so the Mac pushes what the manager says from now on rather than
    /// waiting out the seconds it would otherwise take to notice the polls stopped.
    func leaveManager() async throws {
        _ = try await send(request(.post, "manager/away"))
    }

    /// Start over. The entries go and so does the thread behind them — both, always.
    @discardableResult
    func clearManager() async throws -> ManagerFeed {
        try decode(try await send(request(.post, "manager/clear")))
    }
}
