import Foundation

/// Where the Mac is and how to prove we may talk to it. Typed once, kept in UserDefaults.
public struct ServerSettings: Equatable, Sendable {
    public static let defaultHost = "m2-2.local"
    public static let defaultPort = 4180

    public var host: String
    public var token: String

    public init(host: String = ServerSettings.defaultHost, token: String = "") {
        self.host = host
        self.token = token
    }

    /// Accepts `m2-2.local`, `192.168.178.180:4180`, or a full URL. Nil when unusable.
    ///
    /// `https://deckhand.jurrejan.com` is the one off-LAN form and it is why the port is not
    /// filled in blindly: that host is the NAS Caddy on 443, and 4180 pinned onto it reaches
    /// nothing. Anything spoken over http still means this Mac's daemon, whether or not the
    /// scheme was typed, so that case keeps the default it always had.
    public var baseURL: URL? {
        var text = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://\(text)" }
        guard var parts = URLComponents(string: text), let name = parts.host, !name.isEmpty else {
            return nil
        }
        parts.scheme = parts.scheme ?? "http"
        if parts.scheme != "https" {
            parts.port = parts.port ?? Self.defaultPort
        }
        parts.path = parts.path.hasSuffix("/") ? parts.path : parts.path + "/"
        return parts.url
    }

    public var isComplete: Bool { baseURL != nil && !token.isEmpty }

    /// Whether a Mac found on the network may be written into the address field unasked.
    ///
    /// A pairing that is working is never moved: somebody with two Macs on one network would
    /// otherwise find the phone quietly talking to the other one. There are three openings and
    /// no more — an address nobody has typed, one still on the built-in default, and one this
    /// phone has just failed to reach.
    ///
    /// `answering` is three-valued on purpose. Nil is "not asked", which a check still in
    /// flight and a phone with no token yet both are, and neither of those is a failure — the
    /// same empty-versus-nil distinction `Looking` is built around, one screen along.
    public static func adopts(_ current: String, answering: Bool?) -> Bool {
        let text = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == defaultHost { return true }
        return answering == false
    }

    public func client(urlSession: URLSession = .shared) -> DeckhandClient? {
        guard let baseURL, !token.isEmpty else { return nil }
        return DeckhandClient(baseURL: baseURL, token: token, urlSession: urlSession)
    }

    // MARK: - storage

    private static let hostKey = "deckhand.host"
    private static let tokenKey = "deckhand.token"

    public static func load(from defaults: UserDefaults = .standard) -> ServerSettings {
        ServerSettings(
            host: defaults.string(forKey: hostKey) ?? defaultHost,
            token: defaults.string(forKey: tokenKey) ?? ""
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(host, forKey: Self.hostKey)
        defaults.set(token, forKey: Self.tokenKey)
    }
}
