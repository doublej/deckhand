import Foundation

/// The sessions of one project on one machine, as one block on the rail.
///
/// Grouping is by folder rather than by favourite because a project is the thing a person
/// thinks in: two sessions in the same checkout are working on the same thing whether or not
/// either is starred. A favourite therefore lifts its whole project to the top instead of
/// pulling one session out of it — starring a session must never split its project in two.
public struct ProjectGroup: Identifiable, Hashable, Sendable {
    /// The project's full path on its machine. That and the machine are what make two sessions
    /// the same project — the path alone is not enough, because ``shortened`` renders
    /// `/Users/jurrejan/dev/x` and a second Mac's identical path as the same `~/dev/x`, and two
    /// projects that merely look alike would have become one block.
    public let path: String
    /// Which machine it is on, as the Mac's registry names it. Empty on a one-machine network.
    public let machine: String
    /// The folder itself: `deckhand`.
    public let name: String
    /// Where that folder sits: `~/dev/multi-stack`. Shown under the name, so the two together
    /// are the whole path and neither half is said twice.
    public let parent: String
    /// Newest first, the order the daemon lists them in.
    public let sessions: [Session]
    public let hasFavorite: Bool

    /// A newline joins them because neither half can contain one, so no path can ever be read
    /// as a machine and no machine as a path.
    public var id: String { "\(machine)\n\(path)" }

    public init(path: String, machine: String = "", sessions: [Session], hasFavorite: Bool) {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        self.path = path
        self.machine = machine
        self.name = parts.last ?? path
        self.parent = ProjectGroup.shortened(parts.dropLast())
        self.sessions = sessions
        self.hasFavorite = hasFavorite
    }

    /// Every project with a session on screen, favourites first and then by whichever project
    /// was busiest most recently.
    public static func of(
        _ sessions: [Session], isFavorite: (Session) -> Bool
    ) -> [ProjectGroup] {
        var order: [Key] = []
        var byKey: [Key: [Session]] = [:]
        for session in sessions {
            let key = Key(machine: session.machine ?? "", path: session.cwd)
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(session)
        }
        return order
            .map { key in
                let found = byKey[key] ?? []
                return ProjectGroup(
                    path: key.path,
                    machine: key.machine,
                    sessions: found,
                    hasFavorite: found.contains(where: isFavorite)
                )
            }
            .sorted(by: precedes)
    }

    /// What makes two sessions the same block. A struct rather than a joined string so the
    /// two halves can never be confused for one another while the grouping is being built.
    private struct Key: Hashable {
        let machine: String
        let path: String
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
