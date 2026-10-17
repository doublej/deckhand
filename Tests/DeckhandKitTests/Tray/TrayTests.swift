import Foundation
import Testing

@testable import DeckhandKit

/// The tray is the one place a slip is answered without its page, so what is decoded off the
/// wire and what is sent back are the two things that must not drift.
struct TrayTests {
    private func decode(_ json: String) throws -> TrayFeed {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TrayFeed.self, from: Data(json.utf8))
    }

    private func update(_ id: Int, _ kind: String, session: String = "s", ask: String? = nil,
                        asks: [String]? = nil) -> TrayUpdate {
        TrayUpdate(id: id, type: kind, session: session, name: session, when: Double(id),
                    ask: ask, asks: asks)
    }

    @Test("the Mac's answer decodes, and a kind this build never heard of is opened, not answered")
    func decodesTheWire() throws {
        let feed = try decode("""
        {"open": [{"session": "s", "name": "deckhand", "machine": "m2", "status": "idle",
                   "provider": "claude", "waiting": "",
                   "slips": [{"id": "ship", "title": "Ship it?", "modified": 1.0, "shared": false,
                              "answered": false,
                              "ask": {"kind": "confirm", "accept": "Ship", "decline": "Hold"}},
                             {"id": "new", "title": "?", "modified": 2.0,
                              "ask": {"kind": "slider"}}]}],
         "updates": [{"id": 3, "kind": "answered", "session": "s", "name": "deckhand",
                      "machine": "m2", "when": 5.0, "slip": "ship", "title": "Ship it?",
                      "answer": "Ship"},
                     {"id": 4, "kind": "a-new-word", "session": "s", "name": "deckhand",
                      "when": 6.0}],
         "newest": 4}
        """)
        #expect(feed.open[0].slips[0].ask.accept == "Ship")
        #expect(feed.open[0].slips[1].ask.kind == .page)
        #expect(feed.updates[0].kind == .answered && feed.updates[0].answer == "Ship")
        #expect(feed.updates[1].kind == .other)
    }

    @Test("an answer drawn here is the JSON the page itself would have sent")
    func answersAsThePageWould() throws {
        #expect(SlipAsk.answer(true) == #"{"answer":true}"#)
        let said = try JSONSerialization.jsonObject(with: Data(SlipAsk.answer("a \"b\"").utf8))
        #expect((said as? [String: String])?["answer"] == "a \"b\"")
    }

    @Test("updates are appended by cursor, and a list that went is started again")
    func cursor() {
        var state = TrayState()
        #expect(!state.loaded)
        state.absorb(TrayFeed(updates: [update(1, "called"), update(2, "called")], newest: 2))
        #expect(state.loaded)
        state.absorb(TrayFeed(updates: [], newest: 2))
        #expect(state.updates.map(\.id) == [1, 2])
        state.absorb(TrayFeed(updates: [update(1, "called")], newest: 1))
        #expect(state.updates.map(\.id) == [1] && state.cursor == 1)
    }

    @Test("a slip answered here leaves at once, and its session with it when nothing is left")
    func dropsAnAnsweredSlip() {
        var state = TrayState()
        let slip = TraySlip(id: "ship", title: "Ship?", modified: 0, ask: SlipAsk(kind: .confirm))
        state.absorb(TrayFeed(open: [TraySession(session: "s", name: "s", slips: [slip])]))
        #expect(state.waitingCount == 1)
        state.drop(slip: "ship", of: "s")
        #expect(state.open.isEmpty)
    }

    @Test("a session's finished asks gather into one card that its list clearing closes")
    func workGathers() {
        let items = TrayItem.items([
            update(1, "done", ask: "fix it"),
            update(2, "answered"),
            update(3, "done", ask: "test it"),
            update(4, "done", session: "t", ask: "other"),
            update(5, "finished", asks: ["fix it", "test it"]),
            update(6, "done", ask: "more")
        ])
        guard case .work(let next) = items[0], case .work(let first) = items[1] else {
            Issue.record("expected the newest two to be work cards: \(items)")
            return
        }
        #expect(next.asks == ["more"] && !next.cleared)
        #expect(first.asks == ["fix it", "test it"] && first.cleared && first.id == 1)
        #expect(items.count == 4)
    }
}
