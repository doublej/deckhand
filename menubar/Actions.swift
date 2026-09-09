import Foundation

/// One menu command. It answers with the line the menu shows, never with nothing.
struct Action: Identifiable {
    var id: String { title }
    let title: String
    let perform: @MainActor () async -> String
}

extension Action {
    /// launchd is the daemon's only owner, so start/stop/restart are launchctl verbs on the
    /// agent, not `uv run`: a daemon started from here would die with this app.
    @MainActor static let all: [Action] = [
        Action(title: "Start") {
            await Daemon.launchctl("bootstrap", Daemon.domain, Daemon.plistURL.path)
        },
        Action(title: "Stop") {
            await Daemon.launchctl("bootout", "\(Daemon.domain)/\(Daemon.label)")
        },
        Action(title: "Restart") {
            await Daemon.launchctl("kickstart", "-k", "\(Daemon.domain)/\(Daemon.label)")
        },
        Action(title: "Copy pairing token", perform: Daemon.copyToken),
        Action(title: "Open log", perform: Daemon.openLog)
    ]
}
