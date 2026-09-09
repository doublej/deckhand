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
    public var baseURL: URL? {
        var text = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://\(text)" }
        guard var parts = URLComponents(string: text), let name = parts.host, !name.isEmpty else {
            return nil
        }
        parts.scheme = parts.scheme ?? "http"
        parts.port = parts.port ?? Self.defaultPort
        parts.path = parts.path.hasSuffix("/") ? parts.path : parts.path + "/"
        return parts.url
    }

    public var isComplete: Bool { baseURL != nil && !token.isEmpty }

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
