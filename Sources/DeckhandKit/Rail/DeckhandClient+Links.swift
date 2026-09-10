import Foundation

/// The one links call, in its own file rather than in `DeckhandClient.swift` — the same seam
/// `DeckhandClient+Projects.swift` and `DeckhandClient+Settings.swift` were split on, and for
/// the same 300-line reason.
public extension DeckhandClient {
    /// Which sessions have messaged which inside `within` seconds. Both ends are always on the
    /// listing, so every answer has two rows to draw between.
    ///
    /// Whole seconds, because the Mac's window is a query parameter with a range on it and a
    /// fractional one buys nothing a five-minute default can use.
    func links(within: TimeInterval) async throws -> [SessionLink] {
        let body: LinkList = try await get("sessions/links?within=\(Int(within))")
        return body.links
    }
}

/// The Mac answers with the window it actually used alongside the edges — worth having on a
/// `curl`, and deliberately ignored here: the phone sent the number and already knows it.
private struct LinkList: Decodable {
    let links: [SessionLink]
}
