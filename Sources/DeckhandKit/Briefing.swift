import Foundation

// What the Mac's small model writes about a session: the briefing, the list of what you asked
// for, and what the writing cost. One model run produces all three, off one reading of one
// transcript, which is why the cost stays a rounding error.

/// What a session has been doing since you last spoke to it.
public struct Summary: Codable, Hashable, Sendable {
    public let summary: String?
    /// The first line of it: what you need to know or do, short enough for a list row.
    public var headline: String?
    /// Everything you have asked this session for, and how far each one got.
    public var tasks: [Ask] = []
    /// What writing these has cost. Nothing else in Deckhand spends anything.
    public var spent: Spend?
    public let error: String?
    /// When the Mac wrote this one. Absent means it has never written one for this session.
    public var writtenAt: Double?
    /// A newer one is owed and queued. Not "wrong": what is here is still the last true thing
    /// said about the session, which is why it is shown rather than replaced with a spinner.
    public var stale = false

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        summary = try box.decodeIfPresent(String.self, forKey: .summary)
        headline = try box.decodeIfPresent(String.self, forKey: .headline)
        tasks = try box.decodeIfPresent([Ask].self, forKey: .tasks) ?? []
        spent = try box.decodeIfPresent(Spend.self, forKey: .spent)
        error = try box.decodeIfPresent(String.self, forKey: .error)
        writtenAt = try box.decodeIfPresent(Double.self, forKey: .writtenAt)
        stale = try box.decodeIfPresent(Bool.self, forKey: .stale) ?? false
    }

    /// True when the Mac has never written one. Different from an empty one, which means the
    /// session has genuinely done nothing since you last spoke to it.
    public var isUnwritten: Bool { writtenAt == nil }
}

/// What the briefings for one session have cost since the Mac last started.
///
/// Everything else here is free: utt transcribes on the Mac and the transcripts are read off
/// disk. This one model run is the whole of what Deckhand spends, so it is worth saying out
/// loud rather than leaving to be discovered on a bill.
public struct Spend: Codable, Hashable, Sendable {
    public var runs = 0
    public var tokens = 0
    /// Read from the cache rather than billed as new. Most of the traffic, almost none of it.
    public var cached = 0

    public init(runs: Int = 0, tokens: Int = 0, cached: Int = 0) {
        self.runs = runs
        self.tokens = tokens
        self.cached = cached
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        runs = try box.decodeIfPresent(Int.self, forKey: .runs) ?? 0
        tokens = try box.decodeIfPresent(Int.self, forKey: .tokens) ?? 0
        cached = try box.decodeIfPresent(Int.self, forKey: .cached) ?? 0
    }

    /// One line for the foot of a briefing: what it cost, in the units a person reads.
    public var line: String {
        let thousands = Double(tokens) / 1000
        let size = tokens < 1000 ? "\(tokens) tokens" : String(format: "%.1fk tokens", thousands)
        return "\(runs) briefing\(runs == 1 ? "" : "s") · \(size)"
    }
}

/// One thing you asked a session for, and whether it has got to it.
///
/// Written by the same model run as the briefing, from your own messages — it is your list,
/// not the session's plan, which is why it is short and in your words.
public struct Ask: Codable, Hashable, Sendable, Identifiable {
    public let text: String
    public let state: String

    public init(text: String, state: String) {
        self.text = text
        self.state = state
    }

    public var id: String { text }

    public enum State: Sendable { case todo, doing, done }

    public var progress: State {
        switch state {
        case "done": .done
        case "doing": .doing
        default: .todo
        }
    }
}
