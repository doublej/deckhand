import DeckhandKit
import Foundation
import Observation
import ServiceManagement

/// Everything the Mac app knows: the manager's conversation, the cards the daemon raised, and
/// which of its two panels the person is looking at.
///
/// One poll does both reads, on a one-second tick that only spends a request when it is due —
/// every second while the manager is working, every four while a panel is looked at, every five
/// otherwise. The phone's panel polls the same conversation; what keeps the two from stepping on
/// each other is `watching`, which tells the daemon whether this poll counts as an open panel.
@MainActor
@Observable
final class Desk {
    var settings: ServerSettings
    /// The conversation, oldest first, appended to by id — the phone's `ManagerDesk` rule.
    var entries: [ManagerEntry] = []
    /// What was said and is on its way to the Mac, drawn at once.
    var pending: [String] = []
    var working = false
    var partial = ""
    var doing = ""
    var draft = ""
    var failure: String?
    var opensAtLogin = SMAppService.mainApp.status == .enabled
    /// Handed over by the menu bar icon, the one view alive from launch. See `MenuLabel`.
    var showWindow: (() -> Void)?

    private var cursor = 0
    /// Whether the first poll has answered. Everything it brought is history, never news.
    private var looked = false
    private var alerts = AlertCursor()
    private var lookers: Set<ManagerPanel.Place> = []
    private var due = Date.distantPast
    private let notifier = Notifier()

    init() {
        settings = Self.paired()
        notifier.opened = { [weak self] in self?.open($0) }
        notifier.begin()
    }

    /// Whether a panel is in front of the person. A poll made while it is says so to the daemon,
    /// which then stops pushing the manager's replies to the phone.
    var watching: Bool { !lookers.isEmpty }

    private var pace: TimeInterval { working ? 1 : watching ? 4 : 5 }

    /// The app's one loop, for as long as it runs.
    func run() async {
        while !Task.isCancelled {
            if Date() >= due { await poll() }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    func poll() async {
        due = Date().addingTimeInterval(pace)
        guard let client = settings.client() else {
            failure = "Not paired with a Mac — open Pairing in the menu."
            return
        }
        do {
            let fresh = absorb(try await client.manager(since: cursor, watching: watching))
            if !watching {
                fresh.filter { $0.role == .manager }.forEach(notifier.show)
            }
            alerts.absorb(try await client.alerts(since: alerts.since)).forEach(notifier.show)
            failure = nil
        } catch {
            failure = Self.reason(error)
        }
    }

    /// A panel came into view or left it. The last one leaving tells the daemon at once, so a
    /// reply written in the next seconds is pushed rather than counted as read.
    func look(_ panel: ManagerPanel.Place, active: Bool) {
        let was = watching
        if active { lookers.insert(panel) } else { lookers.remove(panel) }
        guard was != watching else { return }
        if watching {
            Task { await poll() }
        } else {
            Task { try? await settings.client()?.leaveManager() }
        }
    }

    /// Say something to the manager. Drawn at once; the reply arrives by poll. Words that never
    /// reached the Mac go back into the field rather than vanishing.
    func ask(_ text: String) async {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, let client = settings.client() else { return }
        draft = ""
        pending.append(words)
        working = true
        do {
            let entry = try await client.askManager(words)
            pending.removeAll { $0 == words }
            merge([entry])
        } catch {
            pending.removeAll { $0 == words }
            draft = words
            working = false
            failure = Self.reason(error)
            return
        }
        await poll()
    }

    /// Start over: the Mac drops the entries and the thread behind them, both together.
    func clear() async {
        guard let client = settings.client() else { return }
        do {
            _ = try await client.clearManager()
            forget()
        } catch {
            failure = Self.reason(error)
        }
    }

    func pair(_ settings: ServerSettings) {
        settings.save()
        self.settings = settings
        forget()
        looked = false
        alerts = AlertCursor()
        Task { await poll() }
    }

    func setOpensAtLogin(_ wanted: Bool) {
        do {
            if wanted {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            failure = "Could not change the login item: \(error.localizedDescription)"
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Fold one poll in and hand back the entries that are news.
    ///
    /// A newest id below the cursor is the conversation cleared from the phone: ids start again
    /// at 1, so the cursor does too, or nothing would arrive until the count passed the old one.
    private func absorb(_ feed: ManagerFeed) -> [ManagerEntry] {
        if feed.newest < cursor {
            forget()
            return []
        }
        let fresh = merge(feed.entries)
        cursor = max(feed.newest, entries.last?.id ?? 0)
        working = feed.working
        partial = feed.working ? feed.partial ?? "" : ""
        doing = feed.working ? feed.doing ?? "" : ""
        defer { looked = true }
        return looked ? fresh : []
    }

    private func forget() {
        entries.removeAll()
        cursor = 0
    }

    @discardableResult
    private func merge(_ incoming: [ManagerEntry]) -> [ManagerEntry] {
        let known = Set(entries.map(\.id))
        let fresh = incoming.filter { !known.contains($0.id) }
        entries.append(contentsOf: fresh)
        if !fresh.isEmpty { entries.sort { $0.id < $1.id } }
        return fresh
    }

    /// A clicked notification: a session's goes to its pane, the manager's to the window.
    private func open(_ target: Notifier.Target) {
        switch target {
        case .manager:
            showWindow?()
            AppActivation.front()
        case .session(let id):
            Task { await focus(id) }
        }
    }

    /// Bring a session's iTerm window and tab to the front — a clicked card, or a session the
    /// manager named as a link in its answer.
    func focus(_ session: String) async {
        do {
            try await settings.client()?.focus(session)
        } catch {
            failure = Self.reason(error)
        }
    }

    /// What is saved, or else this Mac's own daemon: over loopback, so the daemon never takes
    /// these polls for the phone (`presence.seen` counts every other address as it), and with
    /// the token read straight off its disk, so there is nothing to type.
    private static func paired() -> ServerSettings {
        let saved = ServerSettings.load()
        guard saved.token.isEmpty else { return saved }
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Deckhand/token")
        let token = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return ServerSettings(host: "127.0.0.1",
                              token: token.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func reason(_ error: Error) -> String {
        guard let error = error as? DeckhandError else { return error.localizedDescription }
        switch error {
        case .unauthorized: return "Token rejected by the Mac"
        case .notLive: return "That session is no longer running"
        case .http(let code, let body): return error.detail ?? "Mac said \(code): \(body.prefix(120))"
        case .badResponse: return "Unreadable answer from the Mac"
        }
    }
}
