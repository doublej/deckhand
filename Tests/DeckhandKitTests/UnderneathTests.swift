import Foundation
import Testing

@testable import DeckhandKit

@Suite("Words said into a field")
struct UnderneathTests {
    @Test("an empty field takes the words on their own")
    func intoNothing() {
        #expect(Underneath.words("rename it", under: "", gap: " ") == "rename it")
        // A field that looks empty and is not: whitespace is not content, and a name starting
        // with a space is not a name.
        #expect(Underneath.words("rename it", under: "  \n ", gap: " ") == "rename it")
    }

    /// The whole point of this function. Anything that replaces what is there loses work.
    @Test("what was already there always survives")
    func neverReplaces() {
        #expect(Underneath.words("and the tests", under: "fix the build", gap: " ")
            == "fix the build and the tests")
        #expect(Underneath.words("second half", under: "first half", gap: "\n\n")
            == "first half\n\nsecond half")
    }

    @Test("nothing heard leaves the field as it was")
    func heardNothing() {
        #expect(Underneath.words("", under: "fix the build", gap: " ") == "fix the build")
        #expect(Underneath.words("   ", under: "fix the build", gap: "\n\n") == "fix the build")
        #expect(Underneath.words("", under: "", gap: " ") == "")
    }

    /// The gap is exactly one gap, whatever either half was carrying on its own edges — two
    /// spoken halves arrive with their own trailing newlines and a field with "a \n\n b" in it
    /// reads as three paragraphs.
    @Test("one gap, not whatever the edges were carrying")
    func oneGap() {
        #expect(Underneath.words("  said  ", under: "typed\n", gap: " ") == "typed said")
        #expect(Underneath.words("\nsaid\n", under: " typed ", gap: "\n\n") == "typed\n\nsaid")
    }
}
