import Testing

@testable import DeckhandKit

struct ManagerLinksTests {
    private let sessions = ["rusty-auk": "aaa", "deckhand": "bbb"]

    @Test("a session named in bold or as code becomes its deckhand:// link")
    func linksNamedSessions() {
        let text = "- **rusty-auk** — 1 ask\n- `deckhand` is busy"
        #expect(ManagerLinks.linked(text, sessions: sessions)
            == "- **[rusty-auk](deckhand://sessions/aaa)** — 1 ask\n"
            + "- [deckhand](deckhand://sessions/bbb) is busy")
    }

    /// `deckhand` the product and `deckhand-xr` the folder are not `deckhand` the session.
    @Test("plain words, longer names and names that are not running are left alone")
    func leavesTheRestAlone() {
        let text = "deckhand is building **deckhand-xr**, and **frost-falcon** is quiet"
        #expect(ManagerLinks.linked(text, sessions: sessions) == text)
    }
}
