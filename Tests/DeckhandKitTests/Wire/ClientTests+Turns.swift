import Foundation
import Testing

@testable import DeckhandKit

/// Stepping back through a conversation.
///
/// An `extension ClientTests` rather than a suite of its own, and in its own folder rather than
/// beside it: `StubProtocol` is static, so a second suite stubbing the same transport answers the
/// first one's requests — and `ClientTests.swift` is at the 300-line gate. An extension stays in
/// that suite and so stays serialized with it.
extension ClientTests {
    /// `before` is a cursor counted from the *end* of the file, which is what makes it safe while
    /// the session is still talking: new turns land at the end and never move the boundary an
    /// older page was read back from. `more` is how a screen knows when to stop offering the step.
    @Test("an older page asks for the turns before the ones already held")
    func pagesBackwards() async throws {
        StubProtocol.respond(with: Data(#"{"turns":[],"queued":[],"more":true}"#.utf8))
        #expect(try await client().turns(of: "s", limit: 25, before: 25).more)
        #expect(StubProtocol.lastRequest?.url?.query == "limit=25&before=25")
    }

    /// A subagent's notice and another session's message both arrive with role "user", so
    /// `written_by` is the only thing keeping either of them out of the person's own mouth.
    @Test("a turn somebody else wrote is signed with their name, not with YOU")
    func namesWhoeverWroteIt() async throws {
        StubProtocol.respond(with: Data(#"""
        {"turns":[{"role":"user","text":"hi","written_by":"","timestamp":"t"},
                  {"role":"user","text":"found it","written_by":"recon","timestamp":"t"}],
         "queued":[],"more":false}
        """#.utf8))
        let turns = try await client().turns(of: "s", limit: 25, before: 0).turns
        #expect(turns[0].isUser && turns[0].speaker() == "YOU")
        #expect(!turns[1].isUser && turns[1].speaker() == "RECON")
    }

    /// The Mac and the phone are routinely a version apart, so a daemon that has never heard of
    /// `written_by` must not cost the whole page.
    @Test("a daemon that predates the signature still decodes")
    func toleratesAnOlderDaemon() async throws {
        StubProtocol.respond(with: Data(#"{"turns":[{"role":"user","text":"hi","timestamp":"t"}],"queued":[],"more":false}"#.utf8))
        #expect(try await client().turns(of: "s", limit: 25, before: 0).turns[0].isUser)
    }
}
