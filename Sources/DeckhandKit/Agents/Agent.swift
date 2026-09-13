import Foundation

/// One subagent a session started — a conversation of its own, not a tool call.
///
/// Claude Code already draws that line: it writes a subagent's transcript beside the session's
/// rather than inside it, under `<sessionId>/subagents/`. This is that folder, read by the Mac.
///
/// The join to the conversation is `toolUseId`: the turn that started this agent carries a
/// `Tool` whose `toolId` is the same string. The phone does that join rather than the Mac, which
/// is why a turn can be drawn before the agent listing has arrived and gain its agents when it
/// does, instead of the two having to land together.
public struct Agent: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// The tool call that started it. The other half of the join.
    public let toolUseId: String
    /// `Explore`, `Plan`, `general-purpose` — whatever was asked for.
    public let kind: String
    /// The one line the session wrote about what it wanted. The only human-written sentence about
    /// this agent anywhere, which is why it is the row's title and `kind` is not.
    public let description: String
    /// The model it was given, where one was named. Empty means the default was taken.
    public let model: String
    /// 1 for an agent this session started; deeper for an agent an agent started.
    public let depth: Int
    /// Still going — the session has had no result back from it yet.
    public let running: Bool
    /// How much it has said and how much it has run, so a row means something unopened.
    public let turns: Int
    public let steps: Int
    public let updatedAt: Double

    public init(id: String, toolUseId: String = "", kind: String = "", description: String = "",
                model: String = "", depth: Int = 1, running: Bool = false, turns: Int = 0,
                steps: Int = 0, updatedAt: Double = 0) {
        self.id = id
        self.toolUseId = toolUseId
        self.kind = kind
        self.description = description
        self.model = model
        self.depth = depth
        self.running = running
        self.turns = turns
        self.steps = steps
        self.updatedAt = updatedAt
    }

    /// Tolerant of a daemon that predates any of this, like every other model on this wire: the
    /// Mac is updated by a git pull and the phone by a rebuild, so they are routinely apart.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(String.self, forKey: .id)
        toolUseId = try box.decodeIfPresent(String.self, forKey: .toolUseId) ?? ""
        kind = try box.decodeIfPresent(String.self, forKey: .kind) ?? ""
        description = try box.decodeIfPresent(String.self, forKey: .description) ?? ""
        model = try box.decodeIfPresent(String.self, forKey: .model) ?? ""
        depth = try box.decodeIfPresent(Int.self, forKey: .depth) ?? 1
        running = try box.decodeIfPresent(Bool.self, forKey: .running) ?? false
        turns = try box.decodeIfPresent(Int.self, forKey: .turns) ?? 0
        steps = try box.decodeIfPresent(Int.self, forKey: .steps) ?? 0
        updatedAt = try box.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0
    }

    // No CodingKeys: the client decodes with `.convertFromSnakeCase`, so `tool_use_id` and
    // `updated_at` arrive as `toolUseId` and `updatedAt` already. Spelling them out here would
    // *break* that — the strategy renames the incoming key before any raw value is compared.

    /// What to call it. The session's own sentence where there is one, because `Explore` is what
    /// it is and "Survey the backend" is what it is *for* — and only one of those earns a row.
    public var title: String {
        description.isEmpty ? (kind.isEmpty ? "agent" : kind) : description
    }

    /// The quiet line under the title: what kind, what model, how much it did. A running agent
    /// says what it has done so far, which is the number that keeps moving while you watch it.
    public var line: String {
        var found: [String] = []
        if !kind.isEmpty { found.append(kind) }
        if !model.isEmpty { found.append(model) }
        if depth > 1 { found.append("depth \(depth)") }
        if steps > 0 { found.append(steps == 1 ? "1 step" : "\(steps) steps") }
        return found.joined(separator: " · ")
    }
}

public extension Agent {
    /// The agents still going that none of these turns started.
    ///
    /// A transcript is a page — the last handful of turns — and an agent outlives the call that
    /// started it by design, so the row that would open one is routinely nowhere on screen. That
    /// is measurable rather than theoretical: on this Mac every agent in every live session was
    /// spawned before the visible page began.
    ///
    /// **Running only.** Every agent a session ever started, pinned to the foot of its transcript,
    /// is a second listing nobody asked for; this empties itself when the work does.
    ///
    /// Newest first, off `updatedAt`, because the caller holds them in a dictionary and a
    /// dictionary has no order — without this the rows would shuffle on every poll.
    static func loose(_ agents: [Agent], notIn turns: [Turn]) -> [Agent] {
        let drawn = Set(turns.flatMap(\.tools).filter(\.isAgent).map(\.toolId)
            .filter { !$0.isEmpty })
        return agents
            .filter { $0.running && !drawn.contains($0.toolUseId) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
