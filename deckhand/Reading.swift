import DeckhandKit
import Foundation

/// Everything the app reads off a session: what it said, what it did, what it made, and what
/// you asked it for. Split from `Model.swift`, which keeps the state and the talking — these
/// are all one job, they all go through the same client, and none of them change anything.
@MainActor
extension AppModel {
    func loadTurns(for session: Session, limit: Int = 8) async {
        guard let client = settings.client() else { return }
        await run {
            let rounds = try await client.turns(of: session.sessionId, limit: limit)
            self.turns = rounds.turns
            self.queued[session.sessionId] = rounds.queued
        }
    }

    /// The landscape deck watches several sessions at once, so it fetches them together.
    func loadDeck(limit: Int = 6) async {
        guard let client = settings.client() else { return }
        for session in deckSessions {
            guard let rounds = try? await client.turns(of: session.sessionId, limit: limit) else {
                continue
            }
            deckTurns[session.sessionId] = rounds.turns
        }
    }

    /// Reads every listed session's headline, one at a time.
    ///
    /// The Mac caches on what the session has actually done, so asking again about a session
    /// that has been quiet costs a round trip and no model run. Sequential on purpose: six
    /// sessions summarised at once is six models thinking, and the rail is not worth that.
    func loadHeadlines() async {
        for session in visibleSessions where !summarising.contains(session.sessionId) {
            await loadSummary(for: session, announcing: false)
        }
    }

    /// `announcing` is false for the rail's own sweep: six sessions taking turns to write the
    /// status line would make it flicker through six messages nobody asked for.
    func loadSummary(for session: Session, announcing: Bool = true) async {
        guard let client = settings.client() else { return }
        summarising.insert(session.sessionId)
        defer { summarising.remove(session.sessionId) }
        await run {
            let summary = try await client.summary(of: session.sessionId)
            if let error = summary.error, announcing {
                self.status = error
            }
            // No summary and no error means the session has done nothing since you last spoke.
            // Say that: a card that simply disappears reads as a failure.
            self.summaries[session.sessionId] = summary.summary
                ?? summary.error
                ?? "Nothing since you last spoke"
            self.headlines[session.sessionId] = summary.headline
            // Only when there is one: a session whose summary came back without a list has
            // not withdrawn the list it had, it simply had nothing new to say about it.
            if !summary.tasks.isEmpty { self.tasks[session.sessionId] = summary.tasks }
            self.spend[session.sessionId] = summary.spent
        }
    }

    /// The files this session touched. Asked for when the tab is opened, not polled: it is a
    /// transcript scan on the Mac and nobody is watching a file list change.
    func loadFiles(for session: Session) async {
        guard let client = settings.client() else { return }
        await run {
            self.assets[session.sessionId] = try await client.files(of: session.sessionId)
        }
    }

    /// One file, saved to a temporary URL the caller owns and deletes. Never cached here — a
    /// rendered clip is tens of megabytes and the model outlives the screen showing it.
    func download(_ asset: Asset, in session: Session) async throws -> URL {
        guard let client = settings.client() else { throw DeckhandError.unauthorized }
        return try await client.download(asset, in: session.sessionId)
    }
}
