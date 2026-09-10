import DeckhandKit
import Foundation

/// How the rail is arranged and what is drawn between its rows: the projects its sessions belong
/// to, and which of them have been messaging each other.
///
/// Here rather than in `Model.swift` for the reason every other `extension AppModel` in this app
/// is in its own file — the type is one screen's worth of state per feature, and `Model.swift`
/// holds only what has to be stored on the class itself.
extension AppModel {
    /// The rail's blocks: one per project, starred projects on top.
    var projects: [ProjectGroup] {
        ProjectGroup.of(visibleSessions) { preferences.isFavorite($0) }
    }

    /// Changing how far back the rail looks drops what is on it, so the next poll answers for
    /// the new window rather than leaving the old window's threads fading on screen.
    func setLinkWindow(_ seconds: TimeInterval) {
        preferences.linkWindow = seconds
        preferences.save()
        trails = []
    }

    /// Which sessions have been messaging each other inside the window the person set.
    ///
    /// Failure is deliberately silent and leaves the rail bare: this is decoration on a screen
    /// whose job is the listing, and a Mac that cannot answer has already said so through
    /// `connection`. An older daemon simply 404s here and the app carries on without it.
    func refreshLinks() async {
        guard let client = settings.client(), connection.isHealthy else { return }
        let found = (try? await client.links(within: preferences.linkWindow)) ?? []
        trails = LinkTrail.fold(found)
    }
}
