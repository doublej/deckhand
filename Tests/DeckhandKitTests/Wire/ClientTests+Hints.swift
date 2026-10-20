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

extension ClientTests {
    @Test("a folder's layers come back outermost first, and one layer is written back")
    func readsAndWritesLayers() async throws {
        StubProtocol.respond(with: Data(#"{"path":"/a/b","layers":[{"path":"","hints":["Claude"]},{"path":"/a/b","hints":["Shopify"]}]}"#.utf8))
        let layers = try await client().hintLayers(for: "/a/b")
        #expect(layers == [HintLayer(path: "", hints: ["Claude"]), HintLayer(path: "/a/b", hints: ["Shopify"])])
        #expect(StubProtocol.lastRequest?.url?.query == "path=/a/b")
        StubProtocol.respond(with: Data(#"{"path":"/a/b","hints":["Shopify"]}"#.utf8))
        #expect(try await client().saveHints(HintLayer(path: "/a/b", hints: ["Shopify", ""])).hints == ["Shopify"])
        #expect(StubProtocol.lastRequest?.httpMethod == "PUT")
    }
}
