import Foundation
import Testing

@testable import DeckhandKit

/// The words utt listens for. An `extension ClientTests` for `ClientTests+Aliases.swift`'s reason.
extension ClientTests {
    @Test("the hint list comes back as words, and a Mac that names none means none")
    func decodesHints() async throws {
        StubProtocol.respond(with: Data(#"{"hints":["deckhand","Claude"]}"#.utf8))
        #expect(try await client().hints() == ["deckhand", "Claude"])
        #expect(StubProtocol.lastRequest?.url?.path == "/hints")
        StubProtocol.respond(with: Data(#"{}"#.utf8))
        #expect(try await client().hints().isEmpty)
    }

    @Test("saving the hints keeps the Mac's reading of the list, not the phone's")
    func savesHints() async throws {
        StubProtocol.respond(with: Data(#"{"hints":["Claude"]}"#.utf8))
        #expect(try await client().saveHints(["Claude", " claude", ""]) == ["Claude"])
        #expect(StubProtocol.lastRequest?.httpMethod == "PUT")
        let body = try #require(StubProtocol.lastBody)
        #expect(String(bytes: body, encoding: .utf8)?.contains(#""hints""#) == true)
    }
}
