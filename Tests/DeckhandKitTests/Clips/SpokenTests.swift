import Foundation
import Testing

@testable import DeckhandKit

/// The one property worth proving without a phone: a row says the sentence for a while and then
/// stops, and it stops by being asked rather than by anything running a clock.
@Suite("Spoken")
struct SpokenTests {
    @Test("the words are there the moment they are written")
    func freshAtOnce() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(Spoken("Sent to deckhand by the Mac", at: now).fresh(at: now)
                    == "Sent to deckhand by the Mac")
    }

    /// The wait a person actually spends looking at the row: a round trip and a glance.
    @Test("they last long enough to be read")
    func lastsAGlance() {
        let now = Date(timeIntervalSince1970: 1_000)
        let said = Spoken("Sent to deckhand by the Mac", at: now)
        #expect(said.fresh(at: now.addingTimeInterval(Spoken.keeps - 1)) != nil)
    }

    @Test("and then they are gone, not merely quieter")
    func staleIsNothing() {
        let now = Date(timeIntervalSince1970: 1_000)
        let said = Spoken("Sent to deckhand by the Mac", at: now)
        #expect(said.fresh(at: now.addingTimeInterval(Spoken.keeps)) == nil)
        #expect(said.fresh(at: now.addingTimeInterval(Spoken.keeps * 10)) == nil)
    }

    /// A phone whose clock moved backwards — a manual change, a timezone jump — must not be told
    /// the sentence expired before it was written.
    @Test("a clock that went backwards still shows it")
    func backwardsClock() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(Spoken("Sending…", at: now).fresh(at: now.addingTimeInterval(-60)) == "Sending…")
    }
}
