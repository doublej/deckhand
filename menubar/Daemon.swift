import AppKit
import DeckhandKit

/// The daemon as this Mac sees it: its launchd agent, its files, and a client for its port.
enum Daemon {
    static let label = "com.jurrejan.deckhand"
    static let domain = "gui/\(getuid())"

    private static let home = FileManager.default.homeDirectoryForCurrentUser
    static let plistURL = home.appending(path: "Library/LaunchAgents/\(label).plist")
    static let tokenURL = home.appending(path: "Library/Application Support/Deckhand/token")
    static let logURL = home.appending(path: "Library/Logs/Deckhand/deckhand.log")

    /// Always the loopback address: this app only ever controls the daemon on its own Mac.
    static func client(token: String) -> DeckhandClient {
        DeckhandClient(baseURL: URL(string: "http://127.0.0.1:4180/")!, token: token)
    }

    static func token() -> String? {
        try? String(contentsOf: tokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `DeckhandError` is not a `LocalizedError`, so its `localizedDescription` is the
    /// useless generic one. A `URLError`'s is worth showing — it names the refused connection.
    static func reason(_ error: Error) -> String {
        switch error as? DeckhandError {
        case .unauthorized: "token rejected"
        case .notLive: "not found"
        case .badResponse: "bad response"
        case .http(let code, _): "http \(code)"
        case .none: (error as? URLError)?.localizedDescription ?? "\(error)"
        }
    }

    @MainActor static func copyToken() -> String {
        guard let token = token() else { return "no token at \(tokenURL.path)" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        return "copied (\(token.count) chars)"
    }

    /// Console.app by name: the default handler for a `.log` is whichever text editor
    /// happens to claim the extension, and it will not follow the file as it grows.
    @MainActor static func openLog() -> String {
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            return "no log at \(logURL.path)"
        }
        let console = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
        NSWorkspace.shared.open(
            [logURL], withApplicationAt: console, configuration: NSWorkspace.OpenConfiguration())
        return "opened in Console"
    }

    static func launchctl(_ arguments: String...) async -> String {
        await run("/bin/launchctl", arguments)
    }

    /// stderr folds into stdout so launchctl's complaints — "service already bootstrapped",
    /// "no such process" — land in the menu instead of vanishing.
    private static func run(_ tool: String, _ arguments: [String]) async -> String {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do { try process.run() } catch { return "failed — \(error.localizedDescription)" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(bytes: data, encoding: .utf8) ?? ""
            return describe(process.terminationStatus, output)
        }.value
    }

    private static func describe(_ status: Int32, _ output: String) -> String {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if status == 0 { return text.isEmpty ? "ok" : text }
        return text.isEmpty ? "exit \(status)" : "exit \(status) — \(text)"
    }
}
