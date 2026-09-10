import Foundation
import Testing

@testable import DeckhandKit

/// The manager's conversation on the wire.
///
/// An `extension ClientTests` in the `Wire` folder rather than a suite of its own, for the reason
/// `ClientTests+Turns.swift` gives at the top of it: `StubProtocol` is static, so a second suite
/// stubbing the same transport answers the first one's requests.
extension ClientTests {
    @Test("the cursor is what the phone asks with, and what it is told to ask with next")
    func decodesTheFeed() async throws {
        StubProtocol.respond(with: Data("""
        {"entries":[{"id":7,"role":"person","text":"what is running","said_at":1757000000.0},
                    {"id":8,"role":"manager","text":"three sessions","said_at":1757000001.0}],
         "newest":8,"working":true}
        """.utf8))
        let feed = try await client().manager(since: 6)
        #expect(feed.entries.map(\.id) == [7, 8])
        #expect(feed.entries.first?.role == .person)
        #expect(feed.newest == 8)
        #expect(feed.working)
        #expect(StubProtocol.lastRequest?.url?.query == "since=6")
    }

    /// `newest` is the cursor, not `entries.last?.id`: a poll that brings nothing back still has
    /// to leave the phone asking for the right thing, or it re-fetches the whole conversation.
    @Test("a poll that brought nothing back still carries the cursor")
    func decodesAnEmptyPoll() async throws {
        StubProtocol.respond(with: Data(#"{"entries":[],"newest":12,"working":false}"#.utf8))
        let feed = try await client().manager(since: 12)
        #expect(feed.entries.isEmpty)
        #expect(feed.newest == 12)
    }

    /// The Mac is upgraded by a git pull and the phone by a rebuild, so they are routinely a
    /// version apart. A role this build has never heard of must cost that one entry its shape,
    /// never the whole conversation its decode.
    @Test("a role this build does not know is a note, not a thrown decode")
    func toleratesARoleFromANewerMac() async throws {
        StubProtocol.respond(with: Data("""
        {"entries":[{"id":1,"role":"whistled","text":"something new","said_at":1.0}],
         "newest":1,"working":false}
        """.utf8))
        let feed = try await client().manager()
        #expect(feed.entries.first?.role == .note)
        #expect(feed.entries.first?.text == "something new")
    }

    @Test("a command entry carries the verb and its target")
    func decodesACommand() async throws {
        StubProtocol.respond(with: Data("""
        {"entries":[{"id":3,"role":"command","text":"open deckhand","said_at":1.0,
                     "command":{"action":"open_session","target":"abc-123"}}],
         "newest":3,"working":false}
        """.utf8))
        let entry = try #require(try await client().manager().entries.first)
        #expect(entry.command == ManagerCommand(action: "open_session", target: "abc-123"))
    }

    /// Saying something answers with what was written down, never with the reply: the Mac does
    /// not make the phone wait for a model, and a twenty-second client timeout is why.
    @Test("asking the manager answers with the entry, not the answer")
    func asksTheManager() async throws {
        StubProtocol.respond(with: Data("""
        {"entry":{"id":4,"role":"person","text":"how is deckhand","said_at":1.0},"working":true}
        """.utf8))
        let entry = try await client().askManager("how is deckhand")
        #expect(entry.role == .person)
        #expect(entry.id == 4)
        #expect(StubProtocol.lastRequest?.httpMethod == "POST")
        #expect(StubProtocol.lastRequest?.url?.path == "/manager/say")
    }

    @Test("clearing answers with an empty conversation and a cursor of nothing")
    func clearsTheManager() async throws {
        StubProtocol.respond(with: Data(#"{"entries":[],"newest":0,"working":false}"#.utf8))
        let feed = try await client().clearManager()
        #expect(feed.newest == 0)
        #expect(StubProtocol.lastRequest?.url?.path == "/manager/clear")
    }
}
