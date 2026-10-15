import Foundation

/// What the Mac hands back for the six-digit code on its screen: a token of this phone's own.
public struct Paired: Decodable, Sendable {
    public struct Mac: Decodable, Sendable {
        public let id: String
        public let name: String
    }

    public let token: String
    public let mac: Mac
}

extension DeckhandClient {
    /// Trade the code the Mac is showing for a token. `POST /pair` is the one route besides
    /// `/health` that takes no token, so this client's own token may be empty.
    ///
    /// A refusal arrives as `DeckhandError.http` carrying the Mac's sentence: 403 a wrong code,
    /// 410 no code open, 429 too many tries. The person needs that sentence, not a status.
    public func pair(code: String, name: String) async throws -> Paired {
        var req = request(.post, "pair")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONEncoder().encode(["code": code, "name": name, "kind": "phone"])
        return try decode(try await send(req, body: body))
    }
}
