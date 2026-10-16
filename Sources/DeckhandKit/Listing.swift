import Foundation

/// What a listing says about the Mac as a whole rather than about any one session: how much of
/// the week's token window is gone, and what the rail is running.
///
/// Both of these are facts the terminal statusline on the Mac already puts in front of whoever
/// is sitting at it. A phone in another room has nobody to ask, so they travel with the listing
/// it was going to fetch anyway — neither costs a request of its own.
public struct Listing: Decodable, Sendable {
    public let sessions: [Session]
    /// Absent from a Mac with no statusline cache, and read through a `try?` so a week object
    /// written by something newer than this app costs the listing nothing: a rail of sessions is
    /// worth more than a percentage, and a decoder that throws would lose both.
    public var week: Week?
    /// Every machine the Mac knows about. Empty from `/sessions`, which answers for this Mac
    /// alone, and from a Mac that predates the network — both of which mean the same thing to
    /// every screen: there is one machine and it does not need naming.
    public var machines: [Machine] = []

    enum CodingKeys: String, CodingKey {
        case sessions, week, machines
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try box.decode([Session].self, forKey: .sessions)
        week = (try? box.decodeIfPresent(Week.self, forKey: .week)) ?? nil
        machines = (try? box.decodeIfPresent([Machine].self, forKey: .machines)) ?? []
    }
}

/// How much of this week's token window is spent, and how long until it starts again.
///
/// Deckhand counts none of this itself: the numbers are the ones the Mac's own statusline cache
/// holds, so the phone and the terminal can never quote different figures at each other.
public struct Week: Codable, Hashable, Sendable {
    /// Runs past 100 on a heavy week — the weekly budget is an estimate, not a ceiling. Nothing
    /// here clamps it and nothing draws it as a bar, because a bar at 152% either clips or lies.
    public let pctUsed: Int
    /// How far through the week we are. This is what makes `pctUsed` mean anything at all: 152%
    /// spent at 51% elapsed is the fact worth knowing, and the 152 on its own is not.
    public let pctElapsed: Int
    public let daysRemaining: Double

    public init(pctUsed: Int, pctElapsed: Int, daysRemaining: Double) {
        self.pctUsed = pctUsed
        self.pctElapsed = pctElapsed
        self.daysRemaining = daysRemaining
    }

    /// Spending faster than the week is passing. The one thing the statusline changes colour for,
    /// and the only reason this number is ever anything but quiet.
    public var overPace: Bool { pctUsed > pctElapsed }

    /// Whole days left, cut rather than rounded: three and a half days is three full days, and a
    /// budget is the one thing never to round *up* — "4d" would be promising half a day that is
    /// not there. The half-day itself is in `spoken`, where there is room for all of it.
    public var days: Int { max(0, Int(daysRemaining)) }

    /// "152% · 3d" — what is spent, and when it starts again.
    public var line: String { "\(pctUsed)% · \(days)d" }

    /// The whole of it in words, for anything reading the screen aloud. Two characters cannot
    /// carry the pace, so this is the one place it is said outright.
    public var spoken: String {
        "Week: \(pctUsed) percent spent, \(pctElapsed) percent elapsed, "
            + "resets in \(String(format: "%.1f", daysRemaining)) days"
    }
}

public extension Session {
    /// A Codex thread has no pane and no CLAUDE.md tree, so the Mac refuses rename, focus, compact,
    /// clear, exit, the context tree, the slash commands and the inbox line for it, and the phone
    /// does not offer them. Stop is the exception: the Mac asks Codex to interrupt its own turn.
    var isCodex: Bool { provider == .codex }

    /// An OpenCode session lives in OpenCode's service, not in a pane, and its API does most of
    /// what a pane did: stop, compact, rename, slash commands and the inbox all work without one.
    /// What it has no answer for is the CLAUDE.md tree, clear, exit and bringing a pane forward.
    var isOpenCode: Bool { provider == .opencode }

    /// Claude Code's own session. Nil is a Mac older than the field, which only listed Claude.
    var isClaude: Bool { provider == nil || provider == .claude }

    /// The word a session that is not Claude carries beside its state. Nil for Claude: every
    /// surface was written for one, so it says nothing.
    var providerWord: String? {
        switch provider {
        case .codex: "CODEX"
        case .opencode: "OPENCODE"
        case .claude, nil: nil
        }
    }

    /// What its own replies are labelled with in the conversation.
    var theirWord: String { providerWord ?? "CLAUDE" }

    /// Whether something on the Mac still has it open. An OpenCode session outlives every window
    /// showing it, and the Mac lists the ones touched in the last two hours whether or not a TUI
    /// still has them, so this is the line between "still open" and "happened lately". Every
    /// session nobody asked about is open: a Claude one is listed only while its process runs.
    var isOpen: Bool { inClient ?? true }

    /// The state word its row and its page carry: BUSY while it works, IDLE while it is open and
    /// waiting, OFF once no client has it open. OFF is utt's word for switched off by the person,
    /// which is what closing the last tab showing a session is.
    var runState: RunState { isBusy ? .busy : isOpen ? .idle : .off }

    // What the Mac can do to it, asked by capability rather than by provider, so a screen never
    // has to know which program answers which verb. Claude's controls are keystrokes in a pane;
    // the other two are their own server's API and need none.

    /// Stop the running turn.
    var stops: Bool { !isClaude || pane != nil }
    /// Fold the conversation down: `/compact` in a pane, or OpenCode's own compaction.
    var compacts: Bool { isOpenCode || (isClaude && pane != nil) }
    /// Give it a new name: `/rename` in a pane, or OpenCode's title.
    var renames: Bool { isOpenCode || (isClaude && pane != nil) }
    /// Clear or exit — the two that cannot be undone. Claude Code's commands, typed into a pane.
    var endsByKeys: Bool { isClaude }
    /// Has slash commands and skills the phone can offer by name.
    var takesCommands: Bool { !isCodex }
    /// Has an inbox of prompts admitted and not yet read, which the Mac can clear.
    var hasInbox: Bool { !isCodex }
    /// Runs under a CLAUDE.md tree the Mac can draw.
    var hasContextTree: Bool { isClaude }
    /// Sits in a tmux pane the Mac can bring to the front.
    var isOnTheMac: Bool { isClaude }

    /// "sonnet", out of `claude-sonnet-5`. The family is the whole of what a glance wants; the
    /// build date on a haiku is the first thing that would not fit and the last anyone reads.
    var family: String? {
        guard let model, !model.isEmpty else { return nil }
        let bare = model.hasPrefix("claude-") ? String(model.dropFirst(7)) : model
        return bare.split(separator: "-").first.map(String.init)
    }

    /// What a whole rail of sessions is running, in the one line a footer has for it.
    ///
    /// The model *and* its effort while every session agrees on both; the model alone when only
    /// the effort differs; a count when the models themselves do. Never one session's model on
    /// its own — a footer sits under all of them, and naming one without saying which would be a
    /// footer that lies. Nil when nothing has answered a request yet, which is a cold Mac.
    static func running(_ sessions: [Session]) -> String? {
        let answered = sessions.filter { $0.family != nil }
        let families = Set(answered.compactMap(\.family))
        guard families.count == 1, let family = families.first else {
            return families.isEmpty ? nil : "\(families.count) models"
        }
        let efforts = Set(answered.map(\.effort))
        guard efforts.count == 1, let effort = efforts.first ?? nil else { return family }
        return "\(family) \(effort)"
    }
}

/// Which program a session is. The raw values are the wire words.
///
/// An unknown word decodes as `.claude` rather than throwing, for `ManagerRole`'s reason: the Mac
/// and the phone are routinely a version apart, and a Mac that grows a third provider must not
/// take the whole listing down on a phone nobody has rebuilt. Claude is what every surface was
/// written for, so such a session is offered what a Claude one is and the Mac refuses the rest.
public enum Provider: String, Codable, Sendable {
    case claude, codex, opencode

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Provider(rawValue: raw) ?? .claude
    }
}
