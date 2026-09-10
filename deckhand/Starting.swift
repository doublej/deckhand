import DeckhandKit
import Foundation
import Observation

/// What the project picker knows while it is open.
///
/// Its own object rather than four more properties on `AppModel`, which is at its length gate —
/// and they belong together anyway: all four live and die with one sheet, and nothing outside it
/// ever reads them.
@MainActor
@Observable
final class ProjectPicker {
    /// The Mac's list, fetched when the sheet opens rather than polled: it is four hundred rows
    /// that change when somebody makes a folder, not while you are looking at them.
    var projects: [Project] = []
    /// Where the list came from, when that is worth saying — atlas being down and answering from
    /// its last scan is the case this exists for.
    var caveat: String?
    var loading = false
    /// Which project is opening a terminal right now, by path. One at a time: starting a session
    /// takes seconds on the Mac, and pressing a second row while the first is still opening is
    /// how you end up with two.
    var starting: String?
}

/// Starting a session that does not exist yet.
///
/// Everything else in this app speaks to a session already running on the Mac. This is the one
/// place a new one comes from, and it is two steps: read the Mac's project list, then ask it to
/// open a terminal in one of those folders and run Claude Code there.
///
/// The list is the Mac's, not this app's. Deckhand consumes whatever the Mac keeps — atlas on
/// this machine — and holds no opinion about what a project is, which is why there is nothing
/// here but a fetch and a hand-off.
@MainActor
extension AppModel {
    /// The Mac's project list. Fetched when the picker opens rather than kept current: it is
    /// four hundred rows that change when somebody makes a folder, and the Mac caches it anyway.
    func loadProjects() async {
        guard let client = settings.client() else { return }
        picker.loading = picker.projects.isEmpty
        await run {
            let catalog = try await client.projects()
            self.picker.projects = catalog.projects
            self.picker.caveat = catalog.caveat
        }
        picker.loading = false
    }

    /// Open a terminal in that folder on the Mac and start Claude Code in it.
    ///
    /// Answers with the session, so the caller can go straight into it. Nil when it did not
    /// start, and the reason is already in `status` — a folder Claude Code has never been
    /// trusted in is the common one, and it says so by name rather than as a failure.
    func start(_ project: Project) async -> Session? {
        guard let client = settings.client() else { return nil }
        picker.starting = project.id
        status = "Starting a session in \(project.name)…"
        defer { picker.starting = nil }
        var made: Session?
        await run {
            let session = try await client.startSession(in: project)
            made = session
            self.status = "\(session.name) is up in \(project.name)"
        }
        // The rail is a session out of date the moment this works, and the new row is the whole
        // point of having pressed it.
        if made != nil { await refreshSessions() }
        return made
    }
}
