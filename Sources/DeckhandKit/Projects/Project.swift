import Foundation

/// One folder on the Mac a session could be started in.
///
/// The Mac decides what a project *is* — atlas keeps the list, and Deckhand only consumes it —
/// so nothing here reproduces any of that knowledge. This is the wire, and the phone's whole
/// understanding of a project is these seven fields.
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

    /// Does this row match what has been typed? Matched against everything a person might
    /// reasonably type — the name, the folder path and the description — because a picker over
    /// four hundred rows is only as good as the one field somebody happens to remember.
    public func matches(_ typed: String) -> Bool {
        let wanted = typed.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return true }
        return wanted.split(separator: " ").allSatisfy { word in
            name.lowercased().contains(word)
                || relative.lowercased().contains(word)
                || description.lowercased().contains(word)
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
