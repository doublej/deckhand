import Foundation

/// The whole network in one call, in its own file for the reason `+Filters` is in one:
/// `DeckhandClient.swift` is at its 300-line gate.
public extension DeckhandClient {
    /// Every session on every machine, and the machines themselves.
    ///
    /// One route rather than two. `/sessions` and `/machines` polled separately can disagree
    /// about the same moment — a session listed on a machine the other call has already called
    /// unreachable — and the rail would draw that disagreement.
    func everywhere() async throws -> Listing {
        try await get("sessions/all")
    }
}
