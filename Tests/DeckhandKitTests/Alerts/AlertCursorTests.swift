import Testing

@testable import DeckhandKit

/// The Mac app's notifications are only as honest as this cursor: a card shown twice, or one
/// from before the app was running, is a notification that lies about what just happened.
struct AlertCursorTests {
    private func feed(_ ids: [Int], newest: Int? = nil) -> SessionAlerts {
        SessionAlerts(
            alerts: ids.map {
                SessionAlert(id: $0, session: "s", name: "deckhand", kind: "asking", line: "", when: 0)
            },
            newest: newest ?? ids.last ?? 0
        )
    }

    @Test("the first look is history, not news")
    func firstLookIsHistory() {
        var cursor = AlertCursor()
        #expect(cursor.absorb(feed([1, 2, 3])).isEmpty)
        #expect(cursor.since == 3)
    }

    @Test("after that, only what is past the cursor is new")
    func onlyPastTheCursor() {
        var cursor = AlertCursor()
        _ = cursor.absorb(feed([1, 2]))
        #expect(cursor.absorb(feed([2, 3, 4])).map(\.id) == [3, 4])
        #expect(cursor.absorb(feed([], newest: 4)).isEmpty)
        #expect(cursor.since == 4)
    }

    /// Ids start again at 1 with the daemon. Without this the app would show nothing until the new
    /// daemon had raised more cards than the old one ever did.
    @Test("a newest id below the held one is a restart, and the cursor starts over")
    func restartStartsOver() {
        var cursor = AlertCursor()
        _ = cursor.absorb(feed([40]))
        #expect(cursor.absorb(feed([], newest: 2)).isEmpty)
        #expect(cursor.since == 0)
        #expect(cursor.absorb(feed([1, 2])).map(\.id) == [1, 2])
    }
}
