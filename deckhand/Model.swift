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
    var state: RunState {
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
    /// The one line each session needs to say in the rail: what to know, or what to do.
    var headlines: [String: String] = [:]
    /// What you have asked each session for, and how far it has got. Written by the same
    /// model run as the briefing, so it costs nothing on top of it.
    var tasks: [String: [Ask]] = [:]
    /// The files each session touched that you could open. Fetched when you ask for them.
    var assets: [String: [Asset]] = [:]
    /// What you have said to each session that it has not picked up yet. The session's own
    /// inbox, read off its transcript — not a guess made from the shape of the conversation.
    var queued: [String: [Queued]] = [:]
    /// What each session's briefings have cost the Mac since it last started.
    var spend: [String: Spend] = [:]
    /// Sessions whose summary is being written right now, so the screen can say so.
    var summarising: Set<String> = []
    /// The session whose page is open. The rail lights exactly one row, the way utt does.
    var current: String?
    var connection: Connection = .unpaired
    /// The Mac's own address on the network, as the Mac reports it. What a session's `localhost`
    /// means to anything that is not the Mac — this phone included.
    var macAddress: String?
    var status: String?
    /// What you just said, per session, waiting for the real transcript to catch up. It reads
    /// as a turn in the conversation because that is what it is — the session simply has not
    /// written it down yet.
    /// Transcribed, held, and waiting to be read before it goes anywhere.
    var review: [String: String] = [:]
    /// Pictures pinned to those words, per session, until they are sent or discarded.
    var attached: [String: [Snap]] = [:]
    var showsHidden = false

    private let logger = Logger(subsystem: "dev.jurrejan.deckhand", category: "app")

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
            macAddress = health.lan
            logger.info("listed \(found.count) sessions")
        } catch {
            connection = .failed(reason(error))
            logger.error("session refresh failed: \(String(describing: error))")
        }
    }

    /// Stop, compact or clear. Nothing to fetch afterwards: the transcript poll picks up
    /// whatever the session does about it, which is the honest picture either way.
    func control(_ action: Control, of session: Session) async {
        guard let client = settings.client() else { return }
        await run {
            try await client.control(action, of: session.sessionId)
            self.status = "\(action.label) — sent to \(session.name)"
            if action == .clear { self.turns = [] }
        }
    }

    /// Rename a session on the Mac, and move what you had decided about it onto the new name.
    ///
    /// The listing catches up on its own once the session actually runs the command — which
    /// for a busy one is when its turn ends, so the status line says it has been asked rather
    /// than claiming it is done.
    func rename(_ session: Session, to name: String) async {
        guard let client = settings.client() else { return }
        let wanted = name.collapsed
        guard !wanted.isEmpty, wanted != session.name else { return }
        await run {
            try await client.rename(session.sessionId, to: wanted)
            self.preferences.renamed(from: session.name, to: wanted)
            self.preferences.save()
            self.status = session.isBusy
                ? "\(session.name) will be \(wanted) when it finishes this turn"
                : "\(session.name) is now \(wanted)"
        }
    }

    /// Throw away whatever the session's inbox still claims to hold.
    ///
    /// For prompts that outlived the session that was going to read them: killed mid-queue, the
    /// enqueues stay in the transcript with nothing to remove them, and the replay cannot tell
    /// that from a message still waiting.
    func clearQueue(for session: Session) async {
        guard let client = settings.client() else { return }
        await run {
            try await client.clearQueue(of: session.sessionId)
            self.queued[session.sessionId] = []
            self.status = "Cleared \(session.name)'s inbox"
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
        // The clip is on the wire: locking here suspends the app and loses it.
        Awake.hold()
        defer { Awake.release() }
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
            status = Self.outcome(of: receipt, to: session)
            // Fetch rather than fake it: the words are in the session's own transcript within
            // a moment, and showing them from there means they are shown once, in order, and
            // looking like every other thing said in this conversation.
            if receipt.delivered { Task { await self.loadTurns(for: session) } }
            return
        }
        review[session.sessionId] = text
        status = "Read it, then send it"
    }

    /// Sending what was held for review lives in `Snaps.swift`: the words may have pictures
    /// pinned to them, and those have to reach the Mac before the message that names them.

    func discard(for session: Session) {
        review[session.sessionId] = nil
        attached[session.sessionId] = nil
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
            macAddress = health.lan
            status = "\(health.name) \(health.version) at \(health.host)"
        } catch {
            connection = .failed(reason(error))
            status = reason(error)
        }
    }

    /// Not private: `Reading.swift` is the other half of this type.
    func run(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            status = reason(error)
            logger.error("\(String(describing: error))")
        }
    }

    func reason(_ error: Error) -> String {
        guard let error = error as? DeckhandError else { return error.localizedDescription }
        switch error {
        case .unauthorized: return "Token rejected by the Mac"
        case .notLive: return "That session is no longer running"
        case .http(let code, let body): return "Mac said \(code): \(body.prefix(120))"
        case .badResponse: return "Unreadable answer from the Mac"
        }
    }
}
