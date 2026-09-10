import Foundation

/// The sessions of one project on the Mac, as one block on the rail.
///
/// Grouping is by folder rather than by favourite because a project is the thing a person
/// thinks in: two sessions in the same checkout are working on the same thing whether or not
/// either is starred. A favourite therefore lifts its whole project to the top instead of
/// pulling one session out of it — starring a session must never split its project in two.
public struct ProjectGroup: Identifiable, Hashable, Sendable {
    /// The project's full path on the Mac, which is what makes two sessions the same project.
    public let path: String
    /// The folder itself: `deckhand`.
    public let name: String
    /// Where that folder sits: `~/dev/multi-stack`. Shown under the name, so the two together
    /// are the whole path and neither half is said twice.
    public let parent: String
    /// Newest first, the order the daemon lists them in.
    public let sessions: [Session]
    public let hasFavorite: Bool

    public var id: String { path }

    public init(path: String, sessions: [Session], hasFavorite: Bool) {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        self.path = path
        self.name = parts.last ?? path
        self.parent = ProjectGroup.shortened(parts.dropLast())
        self.sessions = sessions
        self.hasFavorite = hasFavorite
    }

    /// Every project with a session on screen, favourites first and then by whichever project
    /// was busiest most recently.
    public static func of(_ sessions: [Session], isFavorite: (String) -> Bool) -> [ProjectGroup] {
        var order: [String] = []
        var byPath: [String: [Session]] = [:]
        for session in sessions {
            if byPath[session.cwd] == nil { order.append(session.cwd) }
            byPath[session.cwd, default: []].append(session)
        }
        return order
            .map { path in
                let found = byPath[path] ?? []
                return ProjectGroup(
                    path: path,
                    sessions: found,
                    hasFavorite: found.contains { isFavorite($0.name) }
                )
            }
            .sorted(by: precedes)
    }

    /// Favourites to the top; below that, the project whose newest session moved last.
    private static func precedes(_ lhs: ProjectGroup, _ rhs: ProjectGroup) -> Bool {
        if lhs.hasFavorite != rhs.hasFavorite { return lhs.hasFavorite }
        return lhs.lastActive > rhs.lastActive
    }

    public var lastActive: Double { sessions.map(\.updatedAt).max() ?? 0 }

    /// `/Users/jurrejan/dev` as `~/dev`. The path belongs to the Mac, so the phone's own home
    /// directory says nothing about it — the `/Users/<someone>` prefix is the only thing that
    /// can be recognised from here, and anything else is shown exactly as the Mac spelled it.
    private static func shortened(_ parts: [String]) -> String {
        guard parts.count >= 2, parts[0] == "Users" else {
            return parts.isEmpty ? "/" : "/" + parts.joined(separator: "/")
        }
        let rest = parts.dropFirst(2)
        return rest.isEmpty ? "~" : "~/" + rest.joined(separator: "/")
    }
}
