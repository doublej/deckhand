import DeckhandKit
import Foundation

/// Everything the app reads off a session: what it said, what it did, what it made, and what
/// you asked it for. Split from `Model.swift`, which keeps the state and the talking — these
/// are all one job, they all go through the same client, and none of them change anything.
@MainActor
extension AppModel {
    /// How many turns a first look at a session fetches, and how many more each step back adds.
    ///
    /// Eight was the number for a long time and it was too few to be a transcript: opening a
    /// session showed the last four exchanges and there was no way to ask for the fifth. The Mac
    /// holds the whole file and does the parsing — it always did — so this is a question about
    /// what to fetch first, not about what exists.
    static let page = 25

    /// The ceiling on one request. The Mac refuses more than this, and a phone drawing two
    /// hundred turns is already asking a lot of a `LazyVStack`.
    static let mostAtOnce = 200

    /// How many turns the live poll should ask for: everything already on screen, so that a page
    /// somebody scrolled back to is not thrown away five seconds later by the poll that keeps the
    /// newest end current. This is the whole of what "keep the history" needs on the phone —
    /// nothing is stored here, it is re-read from the Mac, which is where the transcript lives.
    var shown: Int {
        min(AppModel.mostAtOnce, max(AppModel.page, turns.count))
    }

    /// The newest page. Answers whether the Mac has older turns than these, so the screen can
    /// offer to go back without a second request to find out.
    @discardableResult
    func loadTurns(for session: Session, limit: Int = AppModel.page) async -> Bool {
        guard let client = settings.client() else { return false }
        var more = false
        await run {
            let rounds = try await client.turns(of: session.sessionId, limit: limit)
            self.turns = rounds.turns
            self.queued[session.sessionId] = rounds.queued
            more = rounds.more
        }
        return more
    }

    /// The page before the one on screen, put in front of it. Hands back how many arrived — the
    /// screen needs the count to stay where it was, since everything already drawn has just been
    /// pushed down by exactly that many rows.
    ///
    /// `before` is the number of turns already held, which is a cursor counted from the end of
    /// the file. That is what makes it safe while the session keeps talking: new turns land at
    /// the end and do not move the boundary this is reading back from.
    func loadOlderTurns(for session: Session) async -> (added: Int, more: Bool) {
        guard let client = settings.client() else { return (0, false) }
        let held = turns.count
        var arrived: [Turn] = []
        var more = false
        await run {
            let older = try await client.turns(of: session.sessionId,
                                               limit: AppModel.page,
                                               before: held)
            // The page may have been replaced while this was in flight — a live poll, or another
            // session opened. Prepending to a list that is no longer the one asked about would
            // splice one conversation into another.
            guard self.turns.count == held else { return }
            arrived = older.turns
            more = older.more
            self.turns = older.turns + self.turns
        }
        return (arrived.count, more)
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
