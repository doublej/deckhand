import Foundation
import Testing

@testable import DeckhandKit

/// What a session is told when somebody picks a passage out of a slip and talks about it.
///
/// The words here are the words the session acts on, so every one of these is about the prose being
/// *true*: the passage as it was, the slip named by something a session can find, and a quote that
/// had to be cut saying so rather than quietly ending early.
@Suite("Quoting a slip")
struct QuotingTests {
    @Test("the passage comes first, quoted, with the slip named over it")
    func laysItOut() {
        let said = Quote.prose("the second line is the one that is wrong",
                               about: "Two things I am guessing at",
                               from: "What the footer should say",
                               id: "footer")
        #expect(said == """
        From "What the footer should say" (`footer`):

        > Two things I am guessing at

        the second line is the one that is wrong
        """)
    }

    @Test("a passage of several lines stays several lines, blank ones included")
    func keepsTheShape() {
        let said = Quote.prose("this", about: "one\n\n  two", from: "T", id: "t")
        #expect(said.contains("> one\n>\n>   two"))
    }

    @Test("a slip with no title is named by its slug alone")
    func namesWhatItHas() {
        #expect(Quote.prose("x", about: "y", from: "  ", id: "footer").hasPrefix("From `footer`:"))
        #expect(Quote.prose("x", about: "y", from: "Footer", id: "f")
            .hasPrefix("From \"Footer\" (`f`):"))
    }

    @Test("a selection that was gone is not quoted and not pretended at")
    func saysWhatItCannotQuote() {
        let said = Quote.prose("the footer is too loud", about: "   ", from: "Footer", id: "f")
        #expect(said == """
        About "Footer" (`f`):

        the footer is too loud
        """)
        #expect(!said.contains(">"))
    }

    @Test("nothing said about a passage is the passage alone")
    func quotesWithoutARemark() {
        // The view lays down words or nothing — a quote on its own is not a comment — but the prose
        // stays true if it is ever asked for one.
        let said = Quote.prose("", about: "a line", from: "Footer", id: "f")
        #expect(said == """
        From "Footer" (`f`):

        > a line
        """)
    }

    @Test("a selection past the ceiling is cut on a word and says that it was")
    func saysWhenItIsShort() {
        let long = String(repeating: "word ", count: 600)
        let said = Quote.prose("too much", about: long, from: "Footer", id: "f")
        #expect(said.contains("first \(Quote.longest) characters"))
        #expect(said.contains("…"))
        // On a word, not mid-word: the quote ends with the ellipsis straight after a whole word.
        #expect(said.contains("word…"))
        // And nowhere near the whole thing travelled.
        #expect(said.count < long.count)
    }

    @Test("a selection under the ceiling is untouched and says nothing about a ceiling")
    func leavesAShortOneAlone() {
        let said = Quote.prose("fine", about: String(repeating: "a", count: Quote.longest),
                               from: "F", id: "f")
        #expect(!said.contains("first"))
        #expect(!said.contains("…"))
    }

    @Test("a passage written on Windows does not arrive with a mark on every line")
    func foldsCarriageReturns() {
        let said = Quote.prose("x", about: "one\r\ntwo", from: "F", id: "f")
        #expect(said.contains("> one\n> two"))
        #expect(!said.contains("\r"))
    }
}
