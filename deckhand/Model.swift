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
    /// The slips each session has put on this phone, and whether each has been answered.
    var artifacts: [String: [Artifact]] = [:]
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
    /// How much of the week's token window the Mac has spent. Nil until a listing says.
    var week: Week?
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
    /// What the chain said about the words in that card: what it changed, and whether it is going
    /// to refuse them. Written only through `hold`, so neither can outlive the words it was about.
    var reviewFiltered: [String: Filtered] = [:]
    /// Pictures pinned to those words, per session, until they are sent or discarded.
    var attached: [String: [Snap]] = [:]
    var showsHidden = false
    /// Everything the Mac can do to words on their way in, as the Mac describes it. Global,
    /// because what this Mac *can* do genuinely is: only the chain is per session. The phone
    /// holds no list of its own — `Filtering.swift` is the whole of what it knows about filters.
    var knownFilters: [Filter] = []
    /// The chain being edited, in the order it runs. One step per filter, the off ones included,
    /// so the page has something to draw for a filter nobody has switched on yet.
    var filterChain: [FilterRow] = []
    /// Whose chain that is. A chain belongs to one terminal now, the page is one session's page,
    /// and one is open at a time — so this is the loaded one rather than a cache of all of them.
    /// The Mac is the source of truth either way, and it is one request away.
    var filterSession: Session?
    /// Edited and not yet sent. The save happens on the way off the page rather than on each
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
            let listing = try await client.sessions()
            sessions = listing.sessions
            week = listing.week
            connection = .connected(iterm: health.iterm ?? "ok")
            macAddress = health.lan
            logger.info("listed \(listing.sessions.count) sessions")
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
    ///
    /// Words are held for two reasons and they meet here: because reading first is the setting,
    /// and because a filter refused them — a refusal on the way out is still words that exist and
    /// were said to nobody, and the card is the one place in this app that can hold those.
    private func received(_ receipt: UploadReceipt, for session: Session, confirms: Bool) {
        guard let text = receipt.words, confirms || receipt.stoppedBy != nil else {
            status = outcome(of: receipt, to: session)
            // Fetch rather than fake it: the words are in the session's own transcript within
            // a moment, and showing them from there means they are shown once, in order, and
            // looking like every other thing said in this conversation.
            if receipt.went { Task { await self.loadTurns(for: session) } }
            return
        }
        // What the chain made of them, not what utt heard, and what the chain said about them
        // alongside: a word the card shows differing silently from the word that was spoken is
        // the lie this card exists to prevent.
        hold(text,
             for: session,
             notes: receipt.notes,
             stoppedBy: receipt.stoppedBy,
             because: receipt.deliveryError)
        status = outcome(of: receipt, to: session, held: confirms)
    }

    /// Sending what was held for review lives in `Snaps.swift`: the words may have pictures
    /// pinned to them, and those have to reach the Mac before the message that names them.

    func discard(for session: Session) {
        hold(nil, for: session)
        attached[session.sessionId] = nil
        status = "Discarded"
    }

    /// What actually happened to the clip, in the order the person cares about it. A filter
    /// refusing it comes first: that is the one outcome that looks like success from the outside.
    ///
    /// `held` is the difference between a refusal that has happened and one that is coming. On
    /// the preview path nothing was delivered because nothing was meant to be, so "not sent" is
    /// true and useless; what is worth saying is what Send is about to do.
    func outcome(of receipt: UploadReceipt, to session: Session, held: Bool = false) -> String {
        guard receipt.transcript != nil else {
            return receipt.transcriptError ?? "Sent \(receipt.bytes / 1024) KB, no transcript"
        }
        if let refused = receipt.stoppedBy {
            return held
                ? said("Read it — \(title(of: refused)) will not pass it", notes: receipt.notes)
                : stopped(by: refused, because: receipt.deliveryError, notes: receipt.notes)
        }
        if held { return "Read it, then send it" }
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
        // The Mac's own sentence when it sent one: a refused save says which filter this Mac
        // does not have, which is the one thing a person can act on.
        case .http(let code, let body): return error.detail ?? "Mac said \(code): \(body.prefix(120))"
        case .badResponse: return "Unreadable answer from the Mac"
        }
    }
}
