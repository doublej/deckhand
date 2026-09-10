import Foundation

/// One folder on the Mac a session could be started in.
///
/// The Mac decides what a project *is* — atlas keeps the list, and Deckhand only consumes it —
/// so nothing here reproduces any of that knowledge. This is the wire, and nothing else.
///
/// Everything below `trusted` is carried when a source has it and absent when it does not, which
/// is why they are all defaulted: a Mac with a hand-written `projects.json` and no atlas at all
/// still fills a picker, it just fills it with names and folders.
public struct Project: Codable, Hashable, Identifiable, Sendable {
    public let name: String
    public let path: String
    /// Where it sits under the dev root — `multi-stack/deckhand`. What a person recognises it by:
    /// the leading `/Users/<someone>/dev` is the same on every row and reads as noise.
    public let relative: String
    public let description: String
    /// `swift`, `python`, `node` — atlas's own word for what kind of thing this is.
    public let kind: String
    /// When anything last happened here. The list arrives in this order, newest first.
    public let touchedAt: Double
    /// How many live Claude sessions are already in this folder. The one thing worth knowing
    /// before starting another, and the phone cannot work it out without holding both lists.
    public let live: Int
    /// Whether Claude Code has been trusted in this folder on the Mac. An untrusted folder stops
    /// at a question only somebody at the Mac can answer, so the row says so rather than letting
    /// you press it and find out — and it is still listed, because a project missing from the
    /// list is a worse puzzle than one that explains itself.
    public let trusted: Bool
    /// What it is built with — `sveltekit`, `fastapi`. One word, because one word is the whole of
    /// what the Mac knows: atlas reads the manifest to classify a project and then throws the
    /// dependency list away, so "which libraries does this use" has no answer anywhere on this
    /// wire. This is the nearest true thing.
    public let framework: String
    /// What runs it: `bun`, `uv`, `pnpm`.
    public let runner: String
    /// The branch it is on, and whether the tree is dirty.
    public let branch: String
    public let dirty: Bool
    /// Open beads, where the project tracks any.
    public let issues: Int
    /// The port it serves on, where one is reserved.
    public let port: Int
    /// The names it answers on. About four projects in a hundred have one, which is exactly why
    /// they are worth searching: a domain is the thing a person says out loud, and typing one is
    /// the shortest way to the folder behind it.
    public let domains: [String]
    /// How many Claude sessions this folder has ever had. History, where `live` is now.
    public let sessions: Int

    /// A daemon that predates any of this sends none of it, so every one of them decodes as its
    /// empty value rather than throwing the whole listing away.
    public init(
        name: String, path: String, relative: String = "", description: String = "",
        kind: String = "", touchedAt: Double = 0, live: Int = 0, trusted: Bool = false,
        framework: String = "", runner: String = "", branch: String = "", dirty: Bool = false,
        issues: Int = 0, port: Int = 0, domains: [String] = [], sessions: Int = 0
    ) {
        self.name = name
        self.path = path
        self.relative = relative
        self.description = description
        self.kind = kind
        self.touchedAt = touchedAt
        self.live = live
        self.trusted = trusted
        self.framework = framework
        self.runner = runner
        self.branch = branch
        self.dirty = dirty
        self.issues = issues
        self.port = port
        self.domains = domains
        self.sessions = sessions
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = try box.decode(String.self, forKey: .name)
        path = try box.decode(String.self, forKey: .path)
        relative = try box.decodeIfPresent(String.self, forKey: .relative) ?? ""
        description = try box.decodeIfPresent(String.self, forKey: .description) ?? ""
        kind = try box.decodeIfPresent(String.self, forKey: .kind) ?? ""
        touchedAt = try box.decodeIfPresent(Double.self, forKey: .touchedAt) ?? 0
        live = try box.decodeIfPresent(Int.self, forKey: .live) ?? 0
        trusted = try box.decodeIfPresent(Bool.self, forKey: .trusted) ?? false
        framework = try box.decodeIfPresent(String.self, forKey: .framework) ?? ""
        runner = try box.decodeIfPresent(String.self, forKey: .runner) ?? ""
        branch = try box.decodeIfPresent(String.self, forKey: .branch) ?? ""
        dirty = try box.decodeIfPresent(Bool.self, forKey: .dirty) ?? false
        issues = try box.decodeIfPresent(Int.self, forKey: .issues) ?? 0
        port = try box.decodeIfPresent(Int.self, forKey: .port) ?? 0
        domains = try box.decodeIfPresent([String].self, forKey: .domains) ?? []
        sessions = try box.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
    }

    /// The path is the identity, because the path is what a session is started in. Two folders
    /// can share a name — `app` appears three times on this Mac — and a name is not a handle.
    public var id: String { path }

    public var lastTouched: Date { Date(timeIntervalSince1970: touchedAt) }

    /// What to show under the name: where it lives, and what it is for when it says so.
    public var line: String {
        description.isEmpty ? relative : "\(relative) · \(description)"
    }

    /// The one short thing a row says about its state, or nothing at all. A folder that cannot
    /// be started reads as that first; how many sessions are already in it second.
    public var note: String? {
        if !trusted { return "not trusted yet" }
        switch live {
        case 0: return nil
        case 1: return "1 session here"
        default: return "\(live) sessions here"
        }
    }

    /// The short true things about this folder, in the order they earn their place. Drawn as one
    /// quiet line under the description, so a row costs three lines however much is known about it
    /// — a project with a framework, a branch, a port and two domains must not be four times the
    /// height of one with a name.
    ///
    /// A dirty tree is the branch with a `*` after it, which is git's own shorthand and takes no
    /// room. Nothing here is a badge: they are words on a line, because a capsule beside things
    /// you can actually press reads as something to press.
    public var facts: [String] {
        var found: [String] = []
        for word in [kind, framework, runner] where !word.isEmpty { found.append(word) }
        if !branch.isEmpty { found.append(dirty ? "\(branch)*" : branch) }
        if port > 0 { found.append(":\(port)") }
        if issues > 0 { found.append("\(issues) open") }
        return found + domains
    }

    /// Does this row match what has been typed?
    ///
    /// Every word has to land somewhere, but not all in the same place — so "fastapi deck" narrows
    /// and "sveltekit quiz" finds the one project that is both. Searched across everything a person
    /// might reasonably type, which now includes what it is built with and the names it answers on:
    /// a picker over four hundred rows is only as good as the one field somebody happens to
    /// remember, and for a site that is nearly always its domain.
    public func matches(_ typed: String) -> Bool {
        let wanted = typed.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return true }
        let haystack = ([name, relative, description, kind, framework, runner, branch] + domains)
            .map { $0.lowercased() }
        return wanted.split(separator: " ").allSatisfy { word in
            haystack.contains { $0.contains(word) }
        }
    }
}

/// The project list, and which of the Mac's sources answered.
///
/// The source travels with the list because it is the difference between "atlas told me" and
/// "atlas is down and this is what it last knew". A phone showing a stale list should be able to
/// say so rather than quietly showing yesterday.
public struct Catalog: Codable, Sendable {
    public let projects: [Project]
    public let source: String

    /// What the foot of the picker says about where this came from. Nil when there is nothing
    /// worth saying — atlas answering is the ordinary case and does not need announcing.
    public var caveat: String? {
        switch source {
        case "atlas": nil
        case "atlas-cache": "atlas is not answering — this is its last scan"
        case "file": "from this Mac's own projects.json"
        case "none": "no project list on the Mac"
        default: source
        }
    }
}
