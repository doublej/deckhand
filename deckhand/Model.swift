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
    /// Sessions the Mac has never written a briefing for. Distinct from one that came back
    /// empty, which is a session that has genuinely done nothing since you last spoke.
    var waiting: Set<String> = []
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
    /// Everything the Mac can do to words on their way in, as the Mac describes it. The phone
    /// holds no list of its own: `Filtering.swift` is the whole of what it knows about filters.
    var knownFilters: [Filter] = []
    /// The chain, in the order it runs. One step per filter, the off ones included, so the
    /// settings screen has something to draw for a filter nobody has switched on yet.
    var filterChain: [FilterStep] = []
    /// Edited and not yet sent. The save happens on the way out of Settings rather than on each
    /// change, because a text field changes on every letter.
    var filtersDirty = false

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
        // A filter refused it: the words are held rather than reported and let go of. The review
        // card is the one place in this app where words exist and have not been sent, and it can
        // be edited — which is the only useful answer to a filter that will not pass something.
        if let text = receipt.transcript, receipt.stoppedBy != nil {
            review[session.sessionId] = text
            status = outcome(of: receipt, to: session)
            return
        }
        guard let text = receipt.transcript, confirms else {
            status = outcome(of: receipt, to: session)
            // Fetch rather than fake it: the words are in the session's own transcript within
            // a moment, and showing them from there means they are shown once, in order, and
            // looking like every other thing said in this conversation.
            if receipt.went { Task { await self.loadTurns(for: session) } }
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

    /// What actually happened to the clip, in the order the person cares about it. A filter
    /// refusing it comes first: that is the one outcome that looks like success from the outside.
    func outcome(of receipt: UploadReceipt, to session: Session) -> String {
        guard receipt.transcript != nil else {
            return receipt.transcriptError ?? "Sent \(receipt.bytes / 1024) KB, no transcript"
        }
        if let refused = receipt.stoppedBy {
            return stopped(by: refused, notes: receipt.notes)
        }
        if receipt.delivered {
            return said("Sent to \(session.name) by \(receipt.deliveredBy ?? "the Mac")",
                        notes: receipt.notes)
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
