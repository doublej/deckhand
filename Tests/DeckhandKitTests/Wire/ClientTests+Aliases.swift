import Foundation
import Testing

@testable import DeckhandKit

/// The Mac's word list, and the two pieces of logic that decide what goes on it.
///
/// An `extension ClientTests` in the `Wire` folder rather than a suite of its own, for the reason
/// `ClientTests+Turns.swift` gives at the top of it: `StubProtocol` is static, so a second suite
/// stubbing the same transport answers the first one's requests.
extension ClientTests {
    @Test("the alias list comes back as rows of two")
    func decodesAliases() async throws {
        StubProtocol.respond(with: Data(#"{"aliases":[["deck hand","deckhand"]]}"#.utf8))
        #expect(try await client().aliases() == [["deck hand", "deckhand"]])
        #expect(StubProtocol.lastRequest?.url?.path == "/aliases")
    }

    /// A Mac one version behind, or one that has never been written to. Empty rather than a
    /// throw, the same deal every other tolerant decoder on this wire is on.
    @Test("a daemon that names no aliases means none rather than an error")
    func decodesAnEmptyAliasList() async throws {
        StubProtocol.respond(with: Data(#"{}"#.utf8))
        #expect(try await client().aliases().isEmpty)
    }

    /// What comes back is what the Mac *stored*, which is not what was sent: it drops a row with
    /// nothing on its left. A screen following its own copy would show a list nothing is running.
    @Test("saving an alias keeps the Mac's reading of the list, not the phone's")
    func savesAliases() async throws {
        StubProtocol.respond(with: Data(#"{"aliases":[["deck hand","deckhand"]]}"#.utf8))
        let saved = try await client().saveAliases([["deck hand", "deckhand"], ["", "dropped"]])
        #expect(saved == [["deck hand", "deckhand"]])
        #expect(StubProtocol.lastRequest?.httpMethod == "PUT")
        let body = try #require(StubProtocol.lastBody)
        let sent = try #require(String(bytes: body, encoding: .utf8))
        #expect(sent.contains(#""deck hand""#))
    }
}

/// Splitting a sentence into things to tap, and what a run of them means as an alias.
///
/// Pure, and tested here rather than on a screen for that reason: which exact characters land on
/// the left-hand side of a permanent word list is what decides whether the alias ever fires.
@Suite("Aliasing words")
struct AliasTextTests {
    @Test("a sentence splits on whitespace and nothing else")
    func splitsOnSpaces() {
        #expect(AliasText.words(of: "ask the deck hand,\nplease") ==
                ["ask", "the", "deck", "hand,", "please"])
        #expect(AliasText.words(of: "   ").isEmpty)
    }

    /// The Mac matches whole words, so "deckhand," would be an alias that fires only where the
    /// word happens to end a clause. Trimming the punctuation is what keeps one word one row.
    @Test("punctuation at the ends of a picked run is trimmed and the middle is left alone")
    func trimsEdgePunctuation() {
        #expect(AliasText.heard(["deck", "hand,"]) == "deck hand")
        #expect(AliasText.heard(["(deckhand)"]) == "deckhand")
        #expect(AliasText.heard(["don't"]) == "don't")
        // Unicode files `+` as a symbol rather than punctuation, which is the whole reason
        // `.punctuationCharacters` is the set used here.
        #expect(AliasText.heard(["c++"]) == "c++")
        #expect(AliasText.heard(["—"]).isEmpty)
    }

    /// The same rule `aliases.swap` runs on the Mac. If these two ever disagree, the card shows
    /// one sentence and the session is handed another.
    @Test("the new alias is applied to the words already on the card")
    func swapsOnTheCard() {
        #expect(AliasText.swapped("the deck hand on the deckhandle",
                                  heard: "deck hand", meant: "deckhand") ==
                "the deckhand on the deckhandle")
        #expect(AliasText.swapped("Deck Hand", heard: "deck hand", meant: "deckhand") == "deckhand")
    }

    /// A person typing a Windows path into the right-hand box must get the path. `$1` and `\1`
    /// are both template syntax to `NSRegularExpression`, which is why the replacement is escaped.
    @Test("a replacement is taken as written, never as a group reference")
    func takesTheReplacementLiterally() {
        #expect(AliasText.swapped("open see one", heard: "see one", meant: #"C:\1"#) ==
                #"open C:\1"#)
        #expect(AliasText.swapped("cost of it", heard: "of", meant: "$1") == "cost $1 it")
    }

    @Test("an alias with nothing to match leaves the words alone")
    func leavesWordsAlone() {
        #expect(AliasText.swapped("nothing here", heard: "", meant: "x") == "nothing here")
        #expect(AliasText.swapped("nothing here", heard: "deck hand", meant: "deckhand") ==
                "nothing here")
    }
}
