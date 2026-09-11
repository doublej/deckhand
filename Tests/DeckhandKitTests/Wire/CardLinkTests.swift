import Foundation
import Testing

@testable import DeckhandKit

/// The card's deep link is a wire format like any other here: the widget writes it and the app
/// reads it, and nothing but the spelling joins the two. These are that join, from both ends.
@Suite("Card link")
struct CardLinkTests {
    @Test("a link names its own session")
    func carriesTheSession() throws {
        let link = try #require(CardLink.toSession("7f3a-1c2b"))
        #expect(link.absoluteString == "deckhand://sessions/7f3a-1c2b")
        #expect(CardLink.session(openedBy: link) == "7f3a-1c2b")
    }

    /// The whole point of the change: two cards must not hand the app the same URL, or a tap
    /// opens whichever session the app happens to reach first.
    @Test("two cards are two links")
    func oneLinkPerCard() throws {
        #expect(try #require(CardLink.toSession("7f3a")) != #require(CardLink.toSession("aaaa")))
    }

    @Test("nothing else is a session link", arguments: [
        "deckhand://sessions",          // a scheme with nothing after it
        "deckhand://waiting",           // what the widget pointed at while nothing listened
        "deckhand://sessions/",         // a trailing slash and no id
        "https://sessions/7f3a-1c2b",   // right path, wrong scheme
        "deckhand://manager/7f3a"       // right scheme, a host this build has no case for
    ])
    func refusesTheRest(_ text: String) throws {
        #expect(CardLink.session(openedBy: try #require(URL(string: text))) == nil)
    }

    /// A session id is a UUID today and percent-encoding is invisible — but the link is built
    /// through `URLComponents` precisely so that stops being an assumption, and a round trip is
    /// the only thing that proves it.
    @Test("an id that needs escaping survives the round trip")
    func escapes() throws {
        let link = try #require(CardLink.toSession("a b"))
        #expect(!link.absoluteString.contains(" "))
        #expect(CardLink.session(openedBy: link) == "a b")
    }
}
