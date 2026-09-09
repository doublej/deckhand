import Foundation

/// One page a session wrote for the person holding the phone.
///
/// It is a file in the project — `.deckhand/artifacts/<id>.html` — so the id is both the slug
/// an agent picked and the name of the file, and `title` is the page's own `<title>`. The Mac
/// reads both off disk per request; nothing registers an artifact and nothing cleans one up.
public struct Artifact: Codable, Hashable, Identifiable, Sendable {
    /// The slug an agent picked and a person could read: `release-check`, `which-branch`.
    public let id: String
    /// The page's own `<title>`, which is the only name it has.
    public let title: String
    /// When the page was last written, as epoch seconds — the file's own mtime, named and read
    /// exactly as `Asset.modified` is, because it is the same fact about the same kind of file.
    public let modified: Double
    /// Whether `<id>.answer.json` sits beside the page. A page with no answer file is open, and
    /// asking the same question again is deleting that file — so this flips back, both ways.
    public let answered: Bool

    public init(id: String, title: String, modified: Double, answered: Bool) {
        self.id = id
        self.title = title
        self.modified = modified
        self.answered = answered
    }

    public var changed: Date { Date(timeIntervalSince1970: modified) }
}

/// The listing, tolerant of a key that is not there.
///
/// Same reasoning as `Session.context`: a daemon that predates artifacts costs nothing, and an
/// answer with no `artifacts` key is a Mac with nothing to show rather than a broken one. Spelled
/// out rather than left to a default value, because Swift only synthesises `decodeIfPresent` for
/// a property that is optional — a non-optional with a default still throws on a missing key.
struct ArtifactList: Decodable {
    var artifacts: [Artifact] = []

    // Spelled out too: nothing synthesises `CodingKeys` for a type that decodes itself and
    // never encodes.
    enum CodingKeys: String, CodingKey { case artifacts }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        artifacts = try box.decodeIfPresent([Artifact].self, forKey: .artifacts) ?? []
    }
}

public extension DeckhandClient {
    /// Every page this session has put on the phone, newest first as the Mac sorted them.
    ///
    /// A 404 is read as an empty list rather than as an error. Three things answer one and the
    /// phone deliberately does not tell them apart: a daemon that has never heard of the route
    /// (`{"detail": "Not Found"}`), and a session that has gone
    /// (`{"detail": "no live session with that id"}`). A live session with no `.deckhand/artifacts`
    /// folder is not one of them — that is `200 {"artifacts": []}`.
    ///
    /// Matching on those sentences would be building a screen state on a string. And the only way
    /// the listing 404s for a dead session is if it died between the listing and this call, on a
    /// page where every other request for it is failing loudly at the same moment: an empty
    /// section beside an error that already says the session is gone misleads nobody, where a red
    /// line in a section of a screen that is about to close is worse than nothing.
    func artifacts(of sessionId: String) async throws -> [Artifact] {
        do {
            let body: ArtifactList = try decode(try await send(request(.get, "sessions/\(sessionId)/artifacts")))
            return body.artifacts
        } catch DeckhandError.notLive {
            return []
        }
    }

    /// One page, as the HTML an agent wrote. Handed over whole: the viewer has to put the
    /// policy in front of it before a web view sees any of it, which is not something that can
    /// be done to a stream.
    func page(of id: String, in sessionId: String) async throws -> String {
        let data = try await send(request(.get, "sessions/\(sessionId)/artifacts/\(slug(id))"))
        guard let html = String(bytes: data, encoding: .utf8) else { throw DeckhandError.badResponse }
        return html
    }

    /// The person's answer, on its way to the file beside the page and into the session itself.
    ///
    /// `valueJSON` is the text `JSON.stringify` made of whatever the page passed to
    /// `window.deckhand.respond`, and it is parsed here before it is forwarded — the page was
    /// written by an agent and the app is the boundary, so what leaves this call is JSON the
    /// phone has read rather than a string it was handed. Unparsable text throws and never
    /// reaches the Mac.
    ///
    /// May be called more than once for the same artifact: the person is allowed to change
    /// their mind, and the Mac simply rewrites the answer file.
    ///
    /// By the route the person chose for speaking, because this is the person speaking. The Mac
    /// falls back to its own setting when none is named, which is what an older phone gets.
    func answer(
        _ id: String,
        in sessionId: String,
        valueJSON: String,
        route: DeliveryRoute = .auto
    ) async throws -> Delivery {
        let path = "sessions/\(sessionId)/artifacts/\(slug(id))/answer?route=\(route.rawValue)"
        var req = request(.post, path)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let value = try JSONSerialization.jsonObject(with: Data(valueJSON.utf8),
                                                    options: [.fragmentsAllowed])
        let body = try JSONSerialization.data(withJSONObject: ["value": value],
                                              options: [.fragmentsAllowed])
        return try decode(try await send(req, body: body))
    }

    /// An id in a path rather than in a query. A slug is `[a-z0-9-]` in practice, but it is a
    /// filename an agent picked and a stray space would otherwise make the URL itself invalid.
    private func slug(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    }
}
