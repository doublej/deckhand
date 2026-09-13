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
    /// Sessions that have been messaging each other lately, already folded into one thread per
    /// pair. Empty is the normal state and means the rail draws nothing at all. The rest of the
    /// rail's own logic is in `Views/Rail/Linking.swift`.
    var trails: [LinkTrail] = []
    var turns: [Turn] = []
    /// The subagents of the session on screen, keyed by the tool call that started each — which
    /// is how a turn finds its own without holding a copy. Refreshed with the turns, because an
    /// agent that appeared between two polls belongs to a turn already drawn.
    var agents: [String: Agent] = [:]
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
    /// What the clip in that card cost, press to card. Kept here rather than read back off the
    /// archive, which is a file: the card is redrawn on every keystroke of an edit.
    var reviewTiming: [String: ClipTiming] = [:]
    /// When the Mac answered for a clip whose card has not appeared yet. The last span of the
    /// whole path ends in a view, so it is the one that cannot be closed where it was opened —
    /// see `cardAppeared(for:)`.
    var answeredAt: [String: Date] = [:]
    /// Pictures pinned to those words, per session, until they are sent or discarded.
    var attached: [String: [Snap]] = [:]
    var showsHidden = false
    /// The manager's own state, in its own object — see `Views/Manager/ManagerDesk.swift`.
    /// One object rather than six more properties here, for the reason `picker` is one.
    var manager = ManagerDesk()
    /// The project picker's own state, in its own object — see `Starting.swift`.
    var picker = ProjectPicker()
    var wants = Switchboard()
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
    /// Every clip this phone has recorded, on disk. A clip is moved in here before its upload is
    /// attempted, so a Mac that cannot be reached costs the words rather than the clip —
    /// see `Keeping.swift`, which is the other half of this.
    let archive = ClipArchive()
    /// Which archived clips the words in each session's review card came from. The card holds
    /// words that exist and have been said to nobody, and this is how sending them finally marks
    /// the clips they came from as having arrived.
    var heldClips: [String: [String]] = [:]

    /// Every machine the Mac can see, newest listing wins. Empty until the first one lands,
    /// and empty forever from a Mac that has only itself — which is the same thing to every
    /// screen: nothing to name.
    var machines: [Machine] = []
    /// The machine the rail is showing, or nil for all of them. Here rather than in the view
    /// because `SessionListView` is at its length gate and because the deck reads it too.
    var onlyMachine: String?

    /// Not private: `Keeping.swift` is another half of this type, and a clip going out is the one
    /// thing in this app worth a line in the log whether or not it worked.
    let logger = Logger(subsystem: "dev.jurrejan.deckhand", category: "app")

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
        sessions.filter {
            (showsHidden || !preferences.isHidden($0)) && shows($0.machine)
        }
    }

    var favoriteSessions: [Session] {
        sessions.filter { preferences.isFavorite($0) && shows($0.machine) }
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
        preferences.toggleFavorite(session)
        preferences.save()
    }

    func setHidden(_ session: Session, _ hide: Bool) {
        preferences.setHidden(session, hide)
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
            let listing = try await client.everywhere()
            sessions = listing.sessions
            week = listing.week
            absorb(listing.machines)
            connection = .connected(iterm: health.iterm ?? "ok")
            macAddress = health.lan
            logger.info("listed \(listing.sessions.count) sessions")
        } catch {
            connection = .failed(reason(error))
            logger.error("session refresh failed: \(String(describing: error))")
        }
    }

    /// A clip on its way to a session lives in `Keeping.swift`, because it is filed on this phone
    /// before it is anything else.
    ///
    /// Sending what was held for review lives in `Snaps.swift`: the words may have pictures
    /// pinned to them, and those have to reach the Mac before the message that names them.

    /// The words go. The clips they came from stay — a clip nobody said is the clip the
    /// archive is most for, and "discard" here has only ever meant the text in the card.
    func discard(for session: Session) {
        hold(nil, for: session)
        reviewTiming[session.sessionId] = nil
        answeredAt[session.sessionId] = nil
        unheld(for: session)
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
