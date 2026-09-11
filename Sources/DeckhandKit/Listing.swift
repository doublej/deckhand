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
