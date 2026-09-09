import Foundation
import Testing

@testable import DeckhandKit

@Suite("Fading a quiet session")
struct FadeTests {
    @Test("a session between turns is drawn as the app always draws one")
    func fresh() {
        #expect(Fade.contrast(idleFor: 0) == 1)
        #expect(Fade.contrast(idleFor: Fade.grace - 1) == 1)
    }

    @Test("contrast only ever goes down")
    func monotonic() {
        // The whole promise of this: full is the design and age is the only thing that spends
        // it. A curve that recovered anywhere would mean a row brightening while nobody touched
        // it, which is the one thing the rail must not do.
        let ages: [TimeInterval] = [0, 60, 120, 300, 600, 3600, 3 * 3600, 8 * 3600]
        let values = ages.map(Fade.contrast(idleFor:))
        #expect(values == values.sorted(by: >))
    }

    @Test("dim, never gone, however long ago it was")
    func floor() {
        #expect(Fade.contrast(idleFor: Fade.span) == Fade.floor)
        // Three days. Past the span there is nothing left to say, so it says the same thing.
        #expect(Fade.contrast(idleFor: 3 * 24 * 3600) == Fade.floor)
    }

    @Test("most of the travel is in the first hour, where the decision is")
    func shape() {
        // Stated as numbers rather than as a shape, because the reason for a log curve is these
        // values and nothing else: a linear one reads 0.99 at an hour and spends its whole range
        // on the difference between four hours and eight.
        #expect(abs(Fade.contrast(idleFor: 600) - 0.85) < 0.01)
        #expect(abs(Fade.contrast(idleFor: 3600) - 0.69) < 0.01)
        #expect(abs(Fade.contrast(idleFor: 3 * 3600) - 0.59) < 0.01)
    }

    @Test("a session working right now is full contrast however old its timestamp")
    func busyNeverFades() {
        // `updated_at` is the moment the status last changed, not a heartbeat, so this is the
        // real shape of a long turn: busy, with an hour-old stamp. Measured on this Mac.
        let now = Date()
        let working = session(status: "busy", updatedAt: now.addingTimeInterval(-3600))
        let stopped = session(status: "idle", updatedAt: now.addingTimeInterval(-3600))
        #expect(working.contrast(asOf: now) == 1)
        #expect(stopped.contrast(asOf: now) < 1)
    }

    private func session(status: String, updatedAt: Date) -> Session {
        Session(sessionId: "s1",
                pid: 1,
                name: "deckhand",
                cwd: "/Users/jj/dev",
                folder: "dev",
                status: status,
                updatedAt: updatedAt.timeIntervalSince1970,
                tty: "ttys001",
                pane: nil)
    }
}
