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

    /// Everything the transcript holds, as lines. Not kept on the model: it is large, it is
    /// asked for by hand, and nothing else in the app wants it.
    func raw(for session: Session) async -> [String]? {
        guard let client = settings.client() else { return nil }
        do {
            return try await client.raw(of: session.sessionId)
        } catch {
            status = "Could not read \(session.name)'s transcript"
            return nil
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

    /// Every session's briefing, in one call, off the Mac's disk.
    ///
    /// One request rather than one per session, and no model runs at all: the Mac writes these
    /// on its own cycle and this only collects them. That is what makes the first sweep after a
    /// cold start complete — a reinstalled app knows what the Mac knew a moment ago.
    func loadBriefings() async {
        guard let client = settings.client() else { return }
        guard let written = try? await client.briefings() else { return }
        for (sessionId, briefing) in written {
            absorb(briefing, for: sessionId)
        }
    }

    /// One session's briefing, which also moves it to the front of the Mac's queue. Opening a
    /// session is exactly when its briefing is worth more than any other's.
    func loadSummary(for session: Session, announcing: Bool = true) async {
        guard let client = settings.client() else { return }
        summarising.insert(session.sessionId)
        defer { summarising.remove(session.sessionId) }
        await run {
            let briefing = try await client.summary(of: session.sessionId)
            if let error = briefing.error, announcing { self.status = error }
            self.absorb(briefing, for: session.sessionId)
        }
    }

    /// What a briefing changes on the model, from whichever call brought it.
    private func absorb(_ briefing: Summary, for sessionId: String) {
        // Never written and never blank are different things, and only one of them is news.
        // A session the Mac has not got to yet keeps saying "reading", not "nothing happened".
        if briefing.isUnwritten {
            waiting.insert(sessionId)
        } else {
            waiting.remove(sessionId)
            summaries[sessionId] = briefing.summary
                ?? briefing.error
                ?? "Nothing since you last spoke"
            headlines[sessionId] = briefing.headline
        }
        // Only when there is one: a session whose briefing came back without a list has not
        // withdrawn the list it had, it simply had nothing new to say about it.
        if !briefing.tasks.isEmpty { tasks[sessionId] = briefing.tasks }
        spend[sessionId] = briefing.spent
    }

    /// The files this session touched. Asked for when the tab is opened, not polled: it is a
    /// transcript scan on the Mac and nobody is watching a file list change.
    func loadFiles(for session: Session) async {
        guard let client = settings.client() else { return }
        await run {
            self.assets[session.sessionId] = try await client.files(of: session.sessionId)
        }
    }

    /// The names this session answers to. Handed back rather than kept, and asked for only when
    /// a picker opens: there are getting on for two hundred on this Mac, they are files a person
    /// edits, and a copy on the phone would be a stale copy of something cheap to fetch.
    ///
    /// Empty on a failure rather than a throw, with the reason in the status line — the same
    /// answer `raw(for:)` gives, because it is the same question: a fetch made by hand, for one
    /// screen, where the caller has no sensible thing to do with an error but say so.
    func commands(for session: Session) async -> [SlashCommand] {
        guard let client = settings.client() else { return [] }
        do {
            return try await client.commands(of: session.sessionId)
        } catch {
            status = "Could not read \(session.name)'s commands"
            return []
        }
    }

    /// One file, saved to a temporary URL the caller owns and deletes. Never cached here — a
    /// rendered clip is tens of megabytes and the model outlives the screen showing it.
    func download(_ asset: Asset, in session: Session) async throws -> URL {
        guard let client = settings.client() else { throw DeckhandError.unauthorized }
        return try await client.download(asset, in: session.sessionId)
    }
}
