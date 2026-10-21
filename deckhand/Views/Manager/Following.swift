import DeckhandKit
import Foundation

/// Following a `deckhand://` link: from Safari, a slip, a turn, a notification or a Lock Screen
/// card. `DeepLink` holds the shapes and the rules; this only puts the phone there, through the
/// same slots the manager's own commands use (`route`, `pane`, `slip`), so a link and the manager
/// cannot open a session two different ways.
@MainActor
extension AppModel {
    func follow(_ link: DeepLink) async {
        switch link {
        case .sessions: leave(for: .list)
        case .session(let wanted, let pane): await followSession(wanted, pane: pane)
        case .manager(let say):
            // Laid in the field, never sent: see `DeepLink`.
            if let say { manager.draft = say }
            manager.tab = .manager
            manager.open = true
        case .tray:
            manager.tab = .tray
            manager.open = true
        case .projects: leave(for: .projects)
        case .settings: leave(for: .settings)
        }
    }

    /// A session by id or by name, from a fresh listing for the cold-launch reason `onOpenURL`
    /// gives. One that is not running says so, rather than leaving the phone on the rail with no
    /// reason. `slips/<id>` is one slip; anything else is a pane or a square for `SessionView`.
    private func followSession(_ wanted: String, pane: String?) async {
        await refreshSessions()
        guard let found = sessions.first(where: { $0.sessionId == wanted || $0.name == wanted }) else {
            status = "No session called \(wanted) is running."
            return
        }
        let parts = (pane ?? "").split(separator: "/", maxSplits: 1).map(String.init)
        if parts.count == 2, parts[0] == "slips" {
            manager.slip = LinkedSlip(session: found.sessionId, id: parts[1])
        } else {
            manager.pane = pane
        }
        leave(for: .session(found.sessionId))
    }

    /// Put the drawer back and go: a place behind the drawer is no use with the drawer over it.
    private func leave(for route: ManagerRoute) {
        manager.open = false
        manager.route = route
    }
}
