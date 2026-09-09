import DeckhandKit
import Foundation
import Observation
import OSLog

/// What the Mac looks like from here. Every screen shows this, so it is never a guess.
enum Connection: Equatable {
    case unpaired
    case checking
    case connected(iterm: String)
    case failed(String)

    var label: String {
        switch self {
        case .unpaired: "Not paired — open Pair"
        case .checking: "Reaching the Mac…"
        case .connected(let iterm): iterm == "ok" ? "Connected" : "Connected · \(iterm)"
        case .failed(let why): why
        }
    }

    var isWorking: Bool { self == .checking }
    var isHealthy: Bool { if case .connected = self { true } else { false } }

    /// The same four-letter vocabulary utt uses, so the two apps say a state the same way.
    var pill: PillState {
        switch self {
        case .unpaired: .off
        case .checking: .wait
        case .connected(let iterm): iterm == "ok" ? .online : .wait
        case .failed: .err
        }
    }
}

/// Everything the screens read: the server, the sessions, what they said, what you sent.
@MainActor
@Observable
final class AppModel {
    var settings: ServerSettings
    var preferences: Preferences
    var sessions: [Session] = []
    var turns: [Turn] = []
    var deckTurns: [String: [Turn]] = [:]
    var summaries: [String: String] = [:]
    /// Sessions whose summary is being written right now, so the screen can say so.
    var summarising: Set<String> = []
    /// The session whose page is open. The rail lights exactly one row, the way utt does.
    var current: String?
    var connection: Connection = .unpaired
    var status: String?
    /// What you just said, per session, waiting for the real transcript to catch up. It reads
    /// as a turn in the conversation because that is what it is — the session simply has not
    /// written it down yet.
    var pending: [String: String] = [:]
    /// Transcribed, held, and waiting to be read before it goes anywhere.
    var review: [String: String] = [:]
    var showsHidden = false

    private let logger = Logger(subsystem: "com.jj.Deckhand", category: "app")

    init(settings: ServerSettings = .load(), preferences: Preferences = .load()) {
        self.settings = settings
        self.preferences = preferences
        // Launch arguments (`-deckhand.host`, `-deckhand.token`) land in the same defaults,
        // so an install that was handed the pairing details keeps them after a cold start.
        if settings.isComplete { settings.save() }
        connection = settings.isComplete ? .checking : .unpaired
    }

    var isConfigured: Bool { settings.isComplete }

    var visibleSessions: [Session] {
        sessions.filter { showsHidden || !preferences.isHidden($0.name) }
    }

    var favoriteSessions: [Session] {
        sessions.filter { preferences.isFavorite($0.name) }
    }

    /// The deck shows favourites; with none marked it shows what you can see, so it is never blank.
    var deckSessions: [Session] {
        favoriteSessions.isEmpty ? visibleSessions : favoriteSessions
    }

    func saveSettings() {
        settings.save()
        connection = settings.isComplete ? .checking : .unpaired
        status = nil
    }

    func toggleFavorite(_ session: Session) {
        preferences.toggleFavorite(session.name)
        preferences.save()
    }

    func setHidden(_ session: Session, _ hide: Bool) {
        preferences.setHidden(session.name, hide)
        preferences.save()
    }

    func setTalkMode(_ mode: TalkMode) {
        preferences.talkMode = mode
        preferences.save()
    }

    func setConfirms(_ confirms: Bool) {
        preferences.confirms = confirms
        preferences.save()
    }

    func setRoute(_ route: DeliveryRoute) {
        preferences.route = route
        preferences.save()
    }

    // MARK: - the Mac

    func refreshSessions() async {
        guard let client = settings.client() else {
            connection = .unpaired
            return
        }
        if sessions.isEmpty { connection = .checking }
        do {
            let health = try await client.health()
            let found = try await client.sessions()
            sessions = found
            connection = .connected(iterm: health.iterm ?? "ok")
            logger.info("listed \(found.count) sessions")
        } catch {
            connection = .failed(reason(error))
            logger.error("session refresh failed: \(String(describing: error))")
        }
    }

    func loadTurns(for session: Session, limit: Int = 8) async {
        guard let client = settings.client() else { return }
        await run {
            self.turns = try await client.turns(of: session.sessionId, limit: limit)
            // The session has written it down: the optimistic copy has done its job.
            if let waiting = self.pending[session.sessionId],
               self.turns.contains(where: { $0.isUser && $0.text.contains(waiting) }) {
                self.pending[session.sessionId] = nil
            }
        }
    }

    /// The landscape deck watches several sessions at once, so it fetches them together.
    func loadDeck(limit: Int = 6) async {
        guard let client = settings.client() else { return }
        for session in deckSessions {
            guard let turns = try? await client.turns(of: session.sessionId, limit: limit) else {
                continue
            }
            deckTurns[session.sessionId] = turns
        }
    }

    func loadSummary(for session: Session) async {
        guard let client = settings.client() else { return }
        summarising.insert(session.sessionId)
        defer { summarising.remove(session.sessionId) }
        await run {
            let summary = try await client.summary(of: session.sessionId)
            if let error = summary.error {
                self.status = error
            }
            // No summary and no error means the session has done nothing since you last spoke.
            // Say that: a card that simply disappears reads as a failure.
            self.summaries[session.sessionId] = summary.summary
                ?? summary.error
                ?? "Nothing since you last spoke"
        }
    }

    func focus(_ session: Session) async {
        guard let client = settings.client() else { return }
        await run {
            try await client.focus(session.sessionId)
            self.status = "Focused \(session.name) on the Mac"
        }
    }

    func upload(clip: URL, to session: Session) async {
        guard let client = settings.client() else { return }
        let confirms = preferences.confirms
        status = confirms ? "Transcribing…" : "Sending to \(session.name)…"
        logger.info("uploading clip for \(session.name, privacy: .public)")
        await run {
            let receipt = try await client.upload(
                clip: clip,
                to: session.sessionId,
                route: self.preferences.route,
                deliver: !confirms
            )
            self.logger.info("transcript: \(receipt.transcript ?? "none", privacy: .public)")
            try? FileManager.default.removeItem(at: clip)
            self.received(receipt, for: session, confirms: confirms)
        }
    }

    /// Either it is already on its way, or it is waiting to be read first.
    private func received(_ receipt: UploadReceipt, for session: Session, confirms: Bool) {
        guard let text = receipt.transcript, confirms else {
            pending[session.sessionId] = receipt.delivered ? receipt.transcript : nil
            status = Self.outcome(of: receipt, to: session)
            return
        }
        review[session.sessionId] = text
        status = "Read it, then send it"
    }

    /// Sends what was held for review. The words move from "waiting on you" to "waiting on
    /// the session", which is the same card in two different states.
    func send(_ text: String, to session: Session) async {
        guard let client = settings.client() else { return }
        review[session.sessionId] = nil
        pending[session.sessionId] = text
        status = "Sending to \(session.name)…"
        await run {
            let sent = try await client.say(text, to: session.sessionId, route: self.preferences.route)
            guard sent.delivered else {
                self.pending[session.sessionId] = nil
                self.review[session.sessionId] = text
                self.status = sent.deliveryError ?? "\(session.name) did not take it"
                return
            }
            self.status = "Sent to \(session.name) by \(sent.deliveredBy ?? "the Mac")"
        }
    }

    func discard(for session: Session) {
        review[session.sessionId] = nil
        status = "Discarded"
    }

    /// What actually happened to the clip, in the order the person cares about it.
    static func outcome(of receipt: UploadReceipt, to session: Session) -> String {
        guard receipt.transcript != nil else {
            return receipt.transcriptError ?? "Sent \(receipt.bytes / 1024) KB, no transcript"
        }
        if receipt.delivered {
            return "Sent to \(session.name) by \(receipt.deliveredBy ?? "the Mac")"
        }
        return receipt.deliveryError ?? "Transcribed, but \(session.name) did not take it"
    }

    func checkConnection() async {
        guard let client = settings.client() else {
            connection = .unpaired
            status = "Address or token missing"
            return
        }
        connection = .checking
        do {
            let health = try await client.health()
            connection = .connected(iterm: health.iterm ?? "ok")
            status = "\(health.name) \(health.version) at \(health.host)"
        } catch {
            connection = .failed(reason(error))
            status = reason(error)
        }
    }

    private func run(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            status = reason(error)
            logger.error("\(String(describing: error))")
        }
    }

    private func reason(_ error: Error) -> String {
        guard let error = error as? DeckhandError else { return error.localizedDescription }
        switch error {
        case .unauthorized: return "Token rejected by the Mac"
        case .notLive: return "That session is no longer running"
        case .http(let code, let body): return "Mac said \(code): \(body.prefix(120))"
        case .badResponse: return "Unreadable answer from the Mac"
        }
    }
}
