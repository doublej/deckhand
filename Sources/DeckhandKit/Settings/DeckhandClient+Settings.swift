import Foundation

public extension DeckhandClient {
    /// What this Mac has been set to do.
    ///
    /// Decoded **without** `convertFromSnakeCase`, and this is not tidiness — it is the same trap
    /// `filters()` sits behind, written down in `Sources/DeckhandKit/CLAUDE.md`. The converter
    /// rewrites *dictionary keys* as well as struct keys, and the keys of `projects` are folder
    /// paths. `/Users/jj/dev/_sandbox/my_thing` would arrive as something else entirely and the
    /// override filed under it would vanish without a word. So the two snake-case field names on
    /// this wire are spelled out in `CodingKeys` instead, where they cost nothing and break
    /// nothing.
    func settings() async throws -> Settings {
        try plain(try await send(request(.get, "settings")))
    }

    /// The whole document, written whole — and what comes back is what was *stored*, which is
    /// not always what was sent: an unknown key is dropped, a model this Mac does not offer is
    /// refused, and a folder that overrides nothing is removed. A screen that kept showing what
    /// it sent would be showing something untrue of the Mac.
    @discardableResult
    func saveSettings(_ settings: Settings) async throws -> Settings {
        var req = request(.put, "settings")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try plain(try await send(req, body: try JSONEncoder().encode(settings)))
    }

    /// One decoder, no key strategy. Its own function rather than a parameter on `decode`, so
    /// that the reason above is attached to the thing it is about.
    private func plain<T: Decodable>(_ data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }
}
