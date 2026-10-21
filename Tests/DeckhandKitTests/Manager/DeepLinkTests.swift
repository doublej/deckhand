import Foundation
import Testing

@testable import DeckhandKit

struct DeepLinkTests {
    private func read(_ text: String) -> DeepLink? {
        URL(string: text).flatMap(DeepLink.init)
    }

    @Test("a Lock Screen card's link still opens its session")
    func cardLinksStillWork() throws {
        let card = try #require(CardLink.toSession("abc-123"))
        #expect(DeepLink(card) == .session("abc-123", pane: nil))
    }

    @Test("a pane, a square and one slip are carried as the words after the session")
    func panesAndSlips() {
        #expect(read("deckhand://sessions/deckhand/summary") == .session("deckhand", pane: "summary"))
        #expect(read("deckhand://sessions/abc/slips") == .session("abc", pane: "slips"))
        #expect(read("deckhand://sessions/abc/slips/which-branch")
            == .session("abc", pane: "slips/which-branch"))
    }

    /// `lastPathComponent` answers "/" here, which would send the rail looking for a session by it.
    @Test("no session named is the list, not a session called /")
    func bareSessionsIsTheList() {
        #expect(read("deckhand://sessions") == .sessions)
        #expect(read("deckhand://sessions/") == .sessions)
    }

    @Test("the manager link carries its words, and empty words are none")
    func managerWords() {
        #expect(read("deckhand://manager") == .manager(say: nil))
        #expect(read("deckhand://manager?say=what%20is%20stuck") == .manager(say: "what is stuck"))
        #expect(read("deckhand://manager?say=") == .manager(say: nil))
    }

    @Test("the other places, and nothing for a link this build does not know")
    func elsewhere() {
        #expect(read("deckhand://tray") == .tray)
        #expect(read("deckhand://projects") == .projects)
        #expect(read("deckhand://settings") == .settings)
        #expect(read("deckhand://waiting") == nil)
        #expect(read("https://sessions/abc") == nil)
    }
}
