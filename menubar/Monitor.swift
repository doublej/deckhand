import DeckhandKit
import Observation

/// What the daemon is doing, polled while the menu is open, plus the result of the last action.
@MainActor @Observable
final class Monitor {
    private(set) var isUp = false
    private(set) var result = "no action yet"
    private var daemon = "unknown"
    private var sessions = "—"
    private var iterm = "—"

    /// Padded so the monospaced font lines the values up into a column.
    var rows: [String] {
        [row("daemon", daemon), row("sessions", sessions), row("iterm", iterm)]
    }

    private func row(_ label: String, _ value: String) -> String {
        label.padding(toLength: 9, withPad: " ", startingAt: 0) + value
    }

    /// Cancelled by SwiftUI when the menu closes, so nothing polls a hidden window.
    func poll() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    /// `/health` needs no token, so a missing token still shows whether the daemon is up.
    func refresh() async {
        do {
            let health = try await Daemon.client(token: "").health()
            isUp = true
            daemon = "up \(health.version)"
            iterm = health.iterm ?? "—"
        } catch {
            isUp = false
            daemon = "down — \(Daemon.reason(error))"
            iterm = "—"
            sessions = "—"
            return
        }
        sessions = await countSessions()
    }

    private func countSessions() async -> String {
        guard let token = Daemon.token() else { return "no token file" }
        do {
            return String(try await Daemon.client(token: token).sessions().count)
        } catch {
            return Daemon.reason(error)
        }
    }

    /// Every action ends up on the same line — success and failure alike.
    /// The state it changed is picked up by the next `poll` tick.
    func perform(_ action: Action) {
        result = "\(action.title): running…"
        Task { result = "\(action.title): \(await action.perform())" }
    }
}
