import DeckhandKit
import Foundation
import Observation

/// What the manager panel knows while it is open.
///
/// Its own object rather than seven more properties on `AppModel`, which is at its length gate.
/// Everything here lives and dies with one panel, and the two things that outlive a poll — the
/// cursor and the line commands are obeyed from — are the reason it is an object at all.
@MainActor
@Observable
final class ManagerDesk {
    /// The conversation, oldest first. Appended to rather than replaced: the Mac only sends what
    /// is new, so a replace would empty the panel on the first poll that brought nothing back.
    var entries: [ManagerEntry] = []
    /// The Mac says a run is in flight. What draws the working line and what makes the poll fast.
    var working = false
    /// Whether the panel is on screen. `ManagerShell` owns the gesture; this is the state it
    /// moves, so the rail's own foot can open the panel without knowing about the drag.
    var open = false

    /// Whether a session's own page is sitting on top of the rail.
    ///
    /// The shell's swipe belongs to the rail and to the deck. Inside a session a sideways drag
    /// already pages between that session's panes and a leading one already leaves it, so a
    /// gesture that watched the whole screen there would be a third meaning for a drag that has
    /// two — it took the pane swipes and the way out with them. Set by `SessionView`, which is
    /// pushed from exactly one place.
    var covered = false
    /// What is typed but not sent.
    var draft = ""
    var sending = false
    var failure: String?

    /// The last entry id the Mac has. What the next poll asks for everything after.
    var cursor = 0
    /// Commands at or below this id are history and are not obeyed. Set once, to whatever the
    /// Mac's newest entry was when this phone first looked — otherwise a relaunch would replay
    /// every piece of navigation the manager has ever asked for, in order, at launch.
    private var obeyFrom: Int?

    /// Where the manager has asked the phone to go, and which pane it asked for. Two slots
    /// rather than one, because they are two gates owned by two different views: the rail owns
    /// which session is pushed, and the session's own page owns which of its five panes shows.
    /// One slot would lose the first of them whenever a run asked for both, which is exactly
    /// what "open deckhand and show me its slips" is. Each is cleared by whoever acts on it.
    var route: ManagerRoute?
    var pane: String?

    /// Fold a poll's answer in, and hand back any commands that are new enough to obey.
    func absorb(_ feed: ManagerFeed) -> [ManagerCommand] {
        if cursor == 0 { entries.removeAll() }
        entries.append(contentsOf: feed.entries)
        cursor = max(feed.newest, entries.last?.id ?? 0)
        working = feed.working
        let floor = obeyFrom ?? feed.newest
        obeyFrom = cursor
        return feed.entries.filter { $0.id > floor }.compactMap(\.command)
    }

    /// Start the conversation over on this phone. The Mac's own clearing is a separate call.
    func forget() {
        entries.removeAll()
        cursor = 0
        obeyFrom = nil
        working = false
    }
}

/// Somewhere the manager has asked the phone to go.
///
/// An enum rather than the wire's two strings, so the screens that act on it are exhaustive:
/// a verb the Mac grows and this build has no case for is dropped at the seam below, where the
/// answer is one line, rather than silently ignored in four `if`s.
enum ManagerRoute: Equatable {
    case session(String)
    case list
    case settings
    case projects
    case refresh

    /// Nil for `open_pane`, which is not the rail's, and for a verb this build has no case for.
    init?(_ command: ManagerCommand) {
        switch command.action {
        case "open_session": self = .session(command.target)
        case "close_session": self = .list
        case "open_settings": self = .settings
        case "open_projects": self = .projects
        case "refresh": self = .refresh
        default: return nil
        }
    }
}

/// Talking to the manager, and doing what it asks.
///
/// The manager is one Claude session running inside the daemon. Everything else in this app
/// speaks to a session on the Mac; this speaks to the thing that speaks to them.
@MainActor
extension AppModel {
    /// One poll. Brings back what is new, and obeys anything the manager asked the phone to do.
    ///
    /// The Mac never makes this wait for a model — a run in flight comes back as `working` and
    /// the answer arrives on a later poll — so this is a cheap call whatever the manager is
    /// doing, and it is why the panel can poll at a second while it is thinking.
    func pollManager() async {
        guard let client = settings.client() else { return }
        do {
            let feed = try await client.manager(since: manager.cursor)
            for command in manager.absorb(feed) {
                if command.action == "open_pane" {
                    manager.pane = command.target
                    manager.open = false
                    continue
                }
                guard let route = ManagerRoute(command) else {
                    manager.failure = "This phone does not know how to \(command.action)."
                    continue
                }
                obey(route)
            }
            manager.failure = nil
        } catch {
            manager.failure = reason(error)
        }
    }

    /// Say something to the manager. The panel shows it at once; the reply arrives by poll.
    func askManager(_ text: String) async {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, let client = settings.client() else { return }
        manager.sending = true
        manager.draft = ""
        // Held true until the poll that brings the first block back, so the panel does not go
        // quiet between the words landing and the model starting. The Mac's own `working` takes
        // over on the next poll and this stops mattering.
        manager.working = true
        defer { manager.sending = false }
        await run {
            let entry = try await client.askManager(words)
            self.manager.entries.append(entry)
            self.manager.cursor = max(self.manager.cursor, entry.id)
        }
        await pollManager()
    }

    /// A clip spoken into the panel. Transcribed on the Mac and handed straight to the manager.
    ///
    /// Never held for review the way a session's clip is. A prompt into a busy session cannot be
    /// undone, which is what the review card exists for; the manager is a conversation and the
    /// worst a mishearing costs here is one more sentence.
    func askManager(clip: URL) async {
        guard let client = settings.client() else { return }
        manager.working = true
        await run {
            let heard = try await client.upload(clip: clip)
            if let error = heard.error {
                self.manager.working = false
                self.manager.failure = error
                return
            }
            if let entry = heard.entry {
                self.manager.entries.append(entry)
                self.manager.cursor = max(self.manager.cursor, entry.id)
            }
        }
        await pollManager()
    }

    /// Start over: the Mac drops the entries and the thread behind them, both together.
    func clearManager() async {
        guard let client = settings.client() else { return }
        await run {
            _ = try await client.clearManager()
            self.manager.forget()
        }
    }

    /// Act on one route. The panel closes for anything that names a place behind it — being
    /// told the phone went somewhere while still looking at the panel is worse than not going.
    /// A refresh is the exception: it moves nothing, so it must not take the panel away either.
    private func obey(_ route: ManagerRoute) {
        if route != .refresh { manager.open = false }
        manager.route = route
    }
}
