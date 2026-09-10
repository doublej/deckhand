import Foundation
import Testing

@testable import DeckhandKit

/// The property worth proving without a phone is the one the narration must never break: a beat
/// is *available*, never *awaited*. Everything below is a way of asking that same question.
@Suite("Clip narration")
struct ClipNarrationTests {
    @Test("a word is ready at every instant of a wait, including its first")
    func alwaysSomethingToSay() {
        #expect(ClipNarration.word(after: 0) == ClipNarration.beats[0].word)
        for tenth in 0...200 {
            #expect(!ClipNarration.word(after: Double(tenth) / 10).isEmpty)
        }
    }

    @Test("the beats run forwards, from zero, with no two due at once")
    func inOrder() {
        #expect(ClipNarration.beats.first?.after == 0)
        for (earlier, later) in zip(ClipNarration.beats, ClipNarration.beats.dropFirst()) {
            #expect(earlier.after < later.after)
        }
    }

    /// A 300 ms round trip is the one that would look broken. It gets one word.
    @Test("a round trip shorter than the first beat shows one word and no more")
    func aShortTripDoesNotFlicker() {
        let said = Set([0, 0.1, 0.2, 0.3].map { ClipNarration.word(after: $0) })
        #expect(said.count == 1)
    }

    /// A median wait is ~2 s. Enough beats to be a story, few enough to be read.
    @Test("a two-second wait says three words, not four")
    func aMedianWaitIsReadable() {
        let said = stride(from: 0, through: 2.0, by: 0.05).map { ClipNarration.word(after: $0) }
        #expect(Set(said).count == 3)
    }

    /// The one that flicked. Spacing them by eye is how it drifted back under a readable gap
    /// last time, so the gap is a named number and this is what holds every beat to it.
    @Test("no beat is on the pill for less than the floor")
    func noBeatFlicks() {
        for (earlier, later) in zip(ClipNarration.beats, ClipNarration.beats.dropFirst()) {
            #expect(later.after - earlier.after >= ClipNarration.floor)
        }
    }

    /// The long tail is a queue at utt, and saying so is the last honest thing there is to say.
    @Test("a wait that outlives the script holds the last beat")
    func aLongWaitHoldsTheTail() {
        let tail = ClipNarration.beats.last!
        #expect(ClipNarration.word(after: tail.after) == tail.word)
        #expect(ClipNarration.word(after: 10) == tail.word)
        #expect(ClipNarration.word(after: 600) == tail.word)
    }

    /// The schedule is what the view redraws on, and it is finite: nothing is polling a clock
    /// after the tail beat, and no entry falls before the wait it belongs to.
    @Test("the schedule is finite, in the future, and leaves the first beat out")
    func theScheduleRunsOut() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let due = ClipNarration.schedule(from: start)
        #expect(due.count == ClipNarration.beats.count - 1)
        #expect(due.allSatisfy { $0 > start })
        #expect(due.last == start.addingTimeInterval(ClipNarration.beats.last!.after))
    }

    /// The names are `ClipTiming`'s names, so the live narration and the receipt afterwards call
    /// the same things the same thing. utt is the only one of them a person sees twice.
    @Test("utt is named here by the name the breakdown gives it")
    func utt() {
        let spoken = ClipNarration.beats.map(\.word).filter { $0.contains("UTT") }
        #expect(spoken.count >= 3)
        #expect(Stage(name: "utt", took: 0).title.contains("utt"))
    }
}
