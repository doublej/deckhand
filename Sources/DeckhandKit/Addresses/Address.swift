import Foundation

/// One place a session's transcript points at — a dev server, a NAS, a site — as the Mac found
/// and checked it (`daemon/…/addresses/`). The phone scans nothing and probes nothing: it draws
/// these rows and picks which of their URLs a tap opens.
///
/// Tolerant like every listing type here: a Mac a version ahead may add keys, and one a version
/// behind answers 404, which the client turns into no rows.
public struct Address: Decodable, Hashable, Sendable, Identifiable {
    /// scheme://host[:port], every spelling of this Mac folded into `localhost`.
    public var origin: String
    /// `url`, `ip` or `domain` — the most specific shape it was ever written in.
    public var kind: String
    /// The paths it was named with, newest first.
    public var paths: [String]
    public var mentions: Int
    /// The session or the person wrote it, rather than only a tool printing it.
    public var said: Bool
    public var inAgents: Bool
    /// `loads`, `locked`, `fails`, `down` or `checking`.
    public var state: String
    /// `mac`, `home`, `public` or `none`; empty while still checking.
    public var reach: String
    public var status: Int
    public var title: String
    public var note: String
    /// The same address on the Mac's LAN address, where a loopback one also answers there.
    public var lanUrl: String
    public var atlas: Registered?
    /// `important`, `recent` or `rest` — the Mac's call (`addresses/ranking.py`), never the phone's.
    public var tier: String
    /// The one reason it is in its tier: "Shared in the conversation", "Staging", "Atlas · eink".
    public var why: String
    /// When it was last named, ISO 8601.
    public var lastAt: String

    public var id: String { origin }

    /// It answered: loads, or is there behind a password.
    public var answers: Bool { state == "loads" || state == "locked" }

    public init(origin: String, kind: String = "url", paths: [String] = [], mentions: Int = 1,
                said: Bool = true, inAgents: Bool = false, state: String = "loads",
                reach: String = "public", status: Int = 200, title: String = "", note: String = "",
                lanUrl: String = "", atlas: Registered? = nil, tier: String = "important",
                why: String = "", lastAt: String = "") {
        self.origin = origin
        self.kind = kind
        self.paths = paths
        self.mentions = mentions
        self.said = said
        self.inAgents = inAgents
        self.state = state
        self.reach = reach
        self.status = status
        self.title = title
        self.note = note
        self.lanUrl = lanUrl
        self.atlas = atlas
        self.tier = tier
        self.why = why
        self.lastAt = lastAt
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        origin = try box.decode(String.self, forKey: .origin)
        kind = try box.decodeIfPresent(String.self, forKey: .kind) ?? "url"
        paths = try box.decodeIfPresent([String].self, forKey: .paths) ?? []
        mentions = try box.decodeIfPresent(Int.self, forKey: .mentions) ?? 1
        said = try box.decodeIfPresent(Bool.self, forKey: .said) ?? false
        inAgents = try box.decodeIfPresent(Bool.self, forKey: .inAgents) ?? false
        state = try box.decodeIfPresent(String.self, forKey: .state) ?? "checking"
        reach = try box.decodeIfPresent(String.self, forKey: .reach) ?? ""
        status = try box.decodeIfPresent(Int.self, forKey: .status) ?? 0
        title = try box.decodeIfPresent(String.self, forKey: .title) ?? ""
        note = try box.decodeIfPresent(String.self, forKey: .note) ?? ""
        lanUrl = try box.decodeIfPresent(String.self, forKey: .lanUrl) ?? ""
        atlas = try box.decodeIfPresent(Registered.self, forKey: .atlas)
        // A Mac from before the tiers sent none: every row is then simply listed, none hidden.
        tier = try box.decodeIfPresent(String.self, forKey: .tier) ?? "recent"
        why = try box.decodeIfPresent(String.self, forKey: .why) ?? ""
        lastAt = try box.decodeIfPresent(String.self, forKey: .lastAt) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case origin, kind, paths, mentions, said, inAgents, state, reach, status, title, note
        case lanUrl, atlas, tier, why, lastAt
    }
}

/// What atlas has on an address: the project, and the dev hostnames that reach it from anywhere.
public struct Registered: Decodable, Hashable, Sendable {
    public var name: String
    public var path: String
    public var local: String
    public var remote: String

    public init(name: String, path: String = "", local: String = "", remote: String = "") {
        self.name = name
        self.path = path
        self.local = local
        self.remote = remote
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = try box.decodeIfPresent(String.self, forKey: .name) ?? ""
        path = try box.decodeIfPresent(String.self, forKey: .path) ?? ""
        local = try box.decodeIfPresent(String.self, forKey: .local) ?? ""
        remote = try box.decodeIfPresent(String.self, forKey: .remote) ?? ""
    }

    enum CodingKeys: String, CodingKey { case name, path, local, remote }
}

/// The route's whole answer. `complete` is false while a check or atlas's registry is still out,
/// and the page polls until it turns true.
public struct AddressListing: Decodable, Sendable {
    public var addresses: [Address] = []
    public var complete = true

    public init(addresses: [Address] = [], complete: Bool = true) {
        self.addresses = addresses
        self.complete = complete
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        addresses = try box.decodeIfPresent([Address].self, forKey: .addresses) ?? []
        complete = try box.decodeIfPresent(Bool.self, forKey: .complete) ?? true
    }

    enum CodingKeys: String, CodingKey { case addresses, complete }
}

public extension DeckhandClient {
    /// Every address this session and its subagents wrote down, checked by the Mac.
    func addresses(of sessionId: String) async throws -> AddressListing {
        try await get("sessions/\(sessionId)/addresses")
    }
}
