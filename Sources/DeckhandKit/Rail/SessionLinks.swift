import Foundation

/// One direction of traffic between two live sessions, as the Mac reports it.
///
/// The daemon only ever answers with edges whose two ends are both on the listing, so a link
/// always has something to draw between. `latest` is epoch seconds, the way the rest of the
/// wire carries time.
public struct SessionLink: Codable, Hashable, Sendable {
    public let source: String
    public let target: String
    public let latest: Double
    public let count: Int
    /// How many of those arrived carrying a `hop-chain` — passed along rather than sent
    /// directly. Read but not drawn; see `LinkTrail` for why.
    public let relayed: Int

    public init(source: String, target: String, latest: Double, count: Int, relayed: Int = 0) {
        self.source = source
        self.target = target
        self.latest = latest
        self.count = count
        self.relayed = relayed
    }

    public var latestAt: Date { Date(timeIntervalSince1970: latest) }
}

/// Two sessions that have been talking, as one thing to draw.
///
/// The wire carries one edge per direction; a back-and-forth conversation is two of them. The
/// screen wants the opposite — one thread between two rows, with traffic on it — so the pair
/// is folded here rather than in the drawing, where it would be recomputed every frame.
public struct LinkTrail: Identifiable, Hashable, Sendable {
    /// The ends, oriented so `source` is the one that spoke most recently.
    public let source: String
    public let target: String
    /// Messages each way inside the window.
    public let forward: Int
    public let back: Int
    /// The most recent message either way. Everything on screen decays from this.
    public let latest: Date
    /// How many messages across both directions arrived carrying a `hop-chain`.
    public let relayed: Int

    /// Both ends have spoken. Drawn differently, because "A is telling B things" and "A and B
    /// are working something out" are not the same event and should not look the same.
    public var isMutual: Bool { back > 0 }

    /// Mostly agents talking to agents with nobody in the loop.
    ///
    /// A message carries a chain exactly when the turn that sent it was itself peer-driven, so
    /// its absence means a person set that turn in motion and its presence means nothing did.
    /// Note what this is *not*: a chained message may carry words a person wrote further
    /// upstream, so this says the link had no human in it, never that no human wrote the text.
    public var isAutonomous: Bool { relayed * 2 > forward + back }

    /// Identity is the pair, not the direction — the same two sessions are the same thread
    /// however the traffic turns around, so it keeps its phase when the direction flips.
    public var id: String { [source, target].sorted().joined(separator: "|") }

    public init(
        source: String,
        target: String,
        forward: Int,
        back: Int,
        latest: Date,
        relayed: Int = 0
    ) {
        self.source = source
        self.target = target
        self.forward = forward
        self.back = back
        self.latest = latest
        self.relayed = relayed
    }

    /// How loudly this should be drawn, 1 at the moment it happened and 0 once it is older
    /// than the window. This is the feature's whole sense of time: the curve holds a fresh
    /// message vivid for a while and then lets it go, rather than fading evenly, so "just
    /// now" and "four minutes ago" are obviously different rather than arithmetically so.
    public func intensity(now: Date = Date(), window: TimeInterval) -> Double {
        guard window > 0 else { return 0 }
        let age = now.timeIntervalSince(latest)
        guard age < window else { return 0 }
        return pow(max(0, 1 - age / window), 1.6)
    }

    /// The pairs to draw, newest first, with each direction's traffic folded in.
    public static func fold(_ links: [SessionLink]) -> [LinkTrail] {
        var pairs: [String: [SessionLink]] = [:]
        for link in links {
            pairs[[link.source, link.target].sorted().joined(separator: "|"), default: []].append(link)
        }
        return pairs.values.compactMap(trail).sorted { $0.latest > $1.latest }
    }

    /// One pair's edges as a thread, oriented towards whichever way spoke last.
    private static func trail(_ edges: [SessionLink]) -> LinkTrail? {
        guard let newest = edges.max(by: { $0.latest < $1.latest }) else { return nil }
        let forward = edges.filter { $0.source == newest.source }
        let back = edges.filter { $0.source != newest.source }
        return LinkTrail(
            source: newest.source,
            target: newest.target,
            forward: forward.reduce(0) { $0 + $1.count },
            back: back.reduce(0) { $0 + $1.count },
            latest: newest.latestAt,
            relayed: edges.reduce(0) { $0 + $1.relayed }
        )
    }
}
