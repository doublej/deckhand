import Foundation
import Testing

@testable import DeckhandKit

/// The diff's one real failure mode is silent: a substitution whose halves come back the wrong way
/// round still renders as a paragraph of words, and reads as a sentence nobody said. So every
/// expectation below is on the span list itself rather than on anything drawn from it.
@Suite("Word diff")
struct TextDiffTests {
    @Test("two identical sentences are one unchanged span")
    func nothingChanged() {
        #expect(diffWords(from: "send it to the session", to: "send it to the session")
            == [.same("send it to the session")])
    }

    @Test("a word appearing is one added span, and the rest stays put")
    func aWordAppears() {
        #expect(diffWords(from: "send it to the session", to: "send it to the busy session")
            == [.same("send it to the "), .added("busy "), .same("session")])
    }

    @Test("a word going is one removed span")
    func aWordGoes() {
        #expect(diffWords(from: "send it to the busy session", to: "send it to the session")
            == [.same("send it to the "), .removed("busy "), .same("session")])
    }

    /// The ordering trap. `CollectionDifference` hands back a removal offset into the *old*
    /// sentence and an insertion offset into the *new* one, so a substitution in the middle is
    /// where a naive merge puts the two halves in the wrong place or the wrong order.
    @Test("a word swapped mid-sentence strikes the old one before the new one")
    func aWordIsSwapped() {
        #expect(diffWords(from: "the quick brown fox", to: "the slow brown fox")
            == [.same("the "), .removed("quick "), .added("slow "), .same("brown fox")])
    }

    /// Two runs at once, far apart, so a merge that reached across an unchanged span would show.
    @Test("two changes in one sentence stay two changes")
    func twoChanges() {
        #expect(diffWords(from: "one two three four five", to: "one nine three four ten")
            == [
                .same("one "), .removed("two "), .added("nine "), .same("three four "),
                .removed("five"), .added("ten")
            ])
    }

    @Test("adjacent words of the same kind merge into one span")
    func neighboursMerge() {
        #expect(diffWords(from: "hold this", to: "hold all of this")
            == [.same("hold "), .added("all of "), .same("this")])
    }

    @Test("an empty side is all of the other one")
    func emptySides() {
        #expect(diffWords(from: "", to: "say something") == [.added("say something")])
        #expect(diffWords(from: "say something", to: "") == [.removed("say something")])
        #expect(diffWords(from: "", to: "").isEmpty)
    }

    /// Whitespace is carried but never compared, so a version that only gained an indent or a
    /// wider gap is not a rewrite — the same rule utt's own `ProcessedTranscript.changed` follows.
    @Test("spacing alone is not a change, and a line break survives one")
    func spacingIsNotARewrite() {
        #expect(diffWords(from: "  keep\tthis  ", to: "keep this") == [.same("keep\tthis")])
        #expect(diffWords(from: "first line\nsecond line", to: "first line\nsecond word")
            == [.same("first line\nsecond "), .removed("line"), .added("word")])
    }
}
