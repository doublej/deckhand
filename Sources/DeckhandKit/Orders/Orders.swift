import Foundation

/// What one session has been told to keep in mind, and how much of it there is room for.
///
/// The cap comes off the Mac rather than being a number this app also knows. It is the Mac that
/// clamps, so a counter drawn against a constant compiled in here is a counter that says "1,340 of
/// 2,000" while the daemon is quietly cutting at 1,200 — the one thing a counter must not do.
///
/// `limit` is optional for the version-skew reason every other addition to this wire is: a daemon
/// older than this feature answers 404 and never gets here, but a daemon that later stops sending
/// the key should cost the pane its counter and nothing else.
public struct Orders: Codable, Sendable, Equatable {
    public var text: String
    public var limit: Int?

    public init(text: String = "", limit: Int? = nil) {
        self.text = text
        self.limit = limit
    }

    /// Whether there is anything to carry. The Mac decides this for itself on the way out — an
    /// empty field adds nothing to a prompt, byte for byte — and this is only the phone agreeing
    /// with it, so nothing on screen claims a session is running under orders it is not.
    public var inForce: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public extension DeckhandClient {
    /// This session's standing orders, and none rather than an error where there is no route.
    ///
    /// Two different 404s answer the same way, exactly as `artifacts(of:)` reasons about its own:
    /// a daemon older than this feature has no such path, and a session that has gone is a 404
    /// everywhere. Neither is worth a red line on a pane whose honest content in both cases is
    /// "nothing standing" — and a dead session is already failing loudly in every other request
    /// on the page at the same moment.
    func orders(of sessionId: String) async throws -> Orders {
        do {
            return try await get("sessions/\(sessionId)/orders")
        } catch DeckhandError.notLive {
            return Orders()
        }
    }

    /// Replace them, and take back what was *stored* rather than what was sent: the Mac strips
    /// anything a terminal would act on and clamps what is too long, so a screen that kept showing
    /// what it typed would be showing something the session will never be told.
    ///
    /// A 404 throws here, unlike the read. A save that went nowhere and said nothing is the one
    /// failure this app is built to refuse — the person has just typed a paragraph.
    @discardableResult
    func saveOrders(_ text: String, of sessionId: String) async throws -> Orders {
        var req = request(.put, "sessions/\(sessionId)/orders")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try decode(try await send(req, body: try JSONEncoder().encode(["text": text])))
    }
}
