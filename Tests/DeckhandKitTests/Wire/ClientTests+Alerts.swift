import Foundation
import Testing

@testable import DeckhandKit

/// The cards the Mac raised, read by the Mac app, and the poll it reads the manager with.
/// An `extension ClientTests` for the `StubProtocol` reason `ClientTests+Manager.swift` gives.
extension ClientTests {
    @Test("the alerts feed decodes the card the Lock Screen gets, with its id")
    func decodesAlerts() async throws {
        StubProtocol.respond(with: Data("""
        {"alerts":[{"id":5,"session":"sid","name":"deckhand","kind":"asking",
                    "line":"the migration needs a decision","when":1757000000.0}],"newest":5}
        """.utf8))
        let feed = try await client().alerts(since: 4)
        #expect(feed.alerts.first?.isAsking == true)
        #expect(feed.alerts.first?.line == "the migration needs a decision")
        #expect(feed.newest == 5)
        #expect(StubProtocol.lastRequest?.url?.path == "/alerts")
        #expect(StubProtocol.lastRequest?.url?.query == "since=4")
    }

    /// A poll from behind a closed panel says so; every other poll's query is left exactly as the
    /// phone has always sent it.
    @Test("a poll with no panel on screen says it is not watching")
    func pollsWithoutWatching() async throws {
        StubProtocol.respond(with: Data(#"{"entries":[],"newest":3,"working":false}"#.utf8))
        _ = try await client().manager(since: 3, watching: false)
        #expect(StubProtocol.lastRequest?.url?.query == "since=3&watching=false")
    }
}
