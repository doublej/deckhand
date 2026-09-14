import Foundation

/// One `just` recipe a project's folder offers — a deploy, a server, anything else its justfile
/// knows how to do. The Mac already knows which recipes are private and what each one needs; this
/// is that answer, not a second reading of the file.
public struct Recipe: Codable, Hashable, Identifiable, Sendable {
    public let name: String
    /// The recipe's own doc comment, or empty when it wrote none.
    public let doc: String
    /// The `[group('…')]` it was tagged with, or empty. Rows are shown grouped when this is there
    /// and flat when it is not, the way `just --list` itself draws them.
    public let group: String
    /// Whether it takes a required argument. There is nowhere on the phone yet to type one, so a
    /// row that needs args is shown but disabled rather than run with nothing and left to fail.
    public let needsArgs: Bool

    public init(name: String, doc: String = "", group: String = "", needsArgs: Bool = false) {
        self.name = name
        self.doc = doc
        self.group = group
        self.needsArgs = needsArgs
    }

    public var id: String { name }
}

/// A project's whole justfile, or the honest absence of one.
public struct RecipeListing: Codable, Sendable {
    public let hasJustfile: Bool
    public let recipes: [Recipe]

    public init(hasJustfile: Bool = false, recipes: [Recipe] = []) {
        self.hasJustfile = hasJustfile
        self.recipes = recipes
    }
}

/// Whether a recipe the phone started is still running, and what it has said so far.
public struct CommandStatus: Codable, Sendable {
    public let running: Bool
    public let pid: Int
    public let startedAt: Double
    /// Nil while it is still running, or absent on a daemon too old to send it.
    public let exitCode: Int?
    /// The tail of its output — the Mac bounds this, so it is always safe to show whole.
    public let log: String

    public init(running: Bool = false, pid: Int = 0, startedAt: Double = 0, exitCode: Int? = nil,
                log: String = "") {
        self.running = running
        self.pid = pid
        self.startedAt = startedAt
        self.exitCode = exitCode
        self.log = log
    }

    /// One word for the row: what happened, in the past tense a person reads at a glance.
    public var verdict: String? {
        guard !running, let exitCode else { return nil }
        return exitCode == 0 ? "finished" : "failed (\(exitCode))"
    }
}
