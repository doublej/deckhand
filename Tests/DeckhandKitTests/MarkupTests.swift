import CoreGraphics
import Foundation
import Testing

@testable import DeckhandKit

/// The words a marked-up picture arrives with.
///
/// Worth testing on its own because this is the half a session actually reads: the flattened
/// picture is a file it has to open, but the numbered list is in the prompt, and if the numbers
/// in it stop lining up with the markers drawn on the picture then the feedback says nothing.
@Suite("What a marked-up picture says")
struct MarkupTests {
    @Test("three places marked reads as three numbered remarks and two paths")
    func threePlaces() {
        let pins = [
            Pin(spot: CGPoint(x: 412, y: 96), words: "this badge is clipped"),
            Pin(spot: CGPoint(x: 88, y: 540), words: "the caption wraps onto four lines"),
            Pin(spot: CGPoint(x: 700, y: 1180), words: "too much air under the footer")
        ]
        #expect(Pin.prose(pins, about: "shot.png", at: "/Users/jj/dev/shot.png",
                          lettered: "A") == """
            Feedback on shot.png, marked A on the attached copy:

            A1. this badge is clipped
            A2. the caption wraps onto four lines
            A3. too much air under the footer

            The unmarked original is at `/Users/jj/dev/shot.png`.
            """)
    }

    @Test("a place marked without words still gets its number")
    func silent() {
        // The numbering cannot skip one: marker 2 is drawn on the picture whether or not anybody
        // typed into it, so item 2 has to exist or every number after it points at the wrong mark.
        let pins = [
            Pin(spot: .zero, words: "the header is the wrong weight"),
            Pin(spot: .zero),
            Pin(spot: .zero, words: "  \n  ")
        ]
        let text = Pin.prose(pins, about: "a.png", at: "/a.png", lettered: "A")
        #expect(text.contains("A1. the header is the wrong weight"))
        #expect(text.contains("A2. look here"))
        // Whitespace is nothing typed, not a remark made of spaces.
        #expect(text.contains("A3. look here"))
    }

    @Test("the numbers follow the order the places were marked, not where they are")
    func order() {
        // Marked bottom-right first, top-left second. Sorted by position these would swap, and
        // then marker 1 on the picture would point at the second thing in the words.
        let pins = [
            Pin(spot: CGPoint(x: 900, y: 1400), words: "this one was marked first"),
            Pin(spot: CGPoint(x: 4, y: 8), words: "this one second")
        ]
        let text = Pin.prose(pins, about: "a.png", at: "/a.png", lettered: "A")
        #expect(text.contains("A1. this one was marked first\nA2. this one second"))
    }

    @Test("a picture with only a drawing on it still names both copies")
    func drawnOnly() {
        let text = Pin.prose([], about: "chart.jpeg", at: "/tmp/chart.jpeg", lettered: "A")
        #expect(text.hasPrefix("Feedback drawn on the attached copy of chart.jpeg."))
        #expect(text.hasSuffix("The unmarked original is at `/tmp/chart.jpeg`."))
        // No list at all rather than an empty one introduced as though it had items in it.
        #expect(!text.contains("1."))
    }

    @Test("a picture pinned to the card is described without a path or a filename")
    func attached() {
        // The one thing this must not do is invent a path. A picture attached to the review card is
        // bytes on the phone until Send uploads it, and the Mac renames what arrives to a
        // timestamp — so both a path and a filename would point at nothing, and a session one
        // character off a file that does not exist is worse off than one told nothing.
        let pins = [
            Pin(spot: CGPoint(x: 12, y: 30), words: "this arrow points at the wrong cell"),
            Pin(spot: CGPoint(x: 40, y: 90))
        ]
        #expect(Pin.prose(pins, lettered: "A") == """
            Feedback on the attached picture, marked A on it:

            A1. this arrow points at the wrong cell
            A2. look here
            """)
        #expect(!Pin.prose(pins, lettered: "A").contains("`"))
        #expect(!Pin.prose(pins, lettered: "A").contains("original"))
    }

    /// A marker sits on top of the thing it is about, so the unmarked copy is not a spare — it is
    /// the only view of whatever marker 3 is covering. It goes up beside the marked one, and this
    /// is the sentence that says so.
    @Test("both copies attached says both are there and still names no path")
    func attachedWithOriginal() {
        let pins = [Pin(spot: CGPoint(x: 12, y: 30), words: "this arrow points at the wrong cell")]
        let text = Pin.prose(pins, withOriginal: true, lettered: "A")

        #expect(text.hasPrefix("Feedback on the attached picture, marked A on it:"))
        #expect(text.contains("A1. this arrow points at the wrong cell"))
        #expect(text.contains("Both copies are attached"))
        #expect(text.contains("unmarked"))
        // The same rule as ever: there is no path until Send uploads it, so none is invented.
        #expect(!text.contains("`"))
        #expect(!text.contains("/"))
    }

    @Test("a drawing with both copies attached still says both are there")
    func drawnWithOriginal() {
        let text = Pin.prose([], withOriginal: true, lettered: "A")

        #expect(text.hasPrefix("Feedback drawn on the attached picture."))
        #expect(text.contains("Both copies are attached"))
    }

    @Test("an attached picture with only a drawing on it says so and stops")
    func attachedDrawnOnly() {
        #expect(Pin.prose([], lettered: "A") == "Feedback drawn on the attached picture.")
    }

    @Test("the ids are the same for a file and for an attached picture")
    func sameNumbers() {
        // The two halves of the feedback are joined by the id on the marker, and the markers
        // are drawn by one function whichever picture they are on. A file's remarks numbered
        // differently from an attachment's would be the one bug neither could be read through.
        let pins = [Pin(spot: .zero, words: "first"), Pin(spot: .zero), Pin(spot: .zero, words: "third")]
        let numbered = ["C1. first", "C2. look here", "C3. third"]
        for line in numbered {
            #expect(Pin.prose(pins, lettered: "C").contains(line))
            #expect(Pin.prose(pins, about: "a.png", at: "/a.png", lettered: "C").contains(line))
        }
    }

    @Test("the original's path is carried exactly as it came")
    func spacedPath() {
        // What a Mac screenshot is really called. The path is the session's way back to the
        // unmarked picture, so a prose line that tidied the spaces out of it would be a dead end.
        let path = "/Users/jj/Desktop/Screen Shot 2026-09-10 at 11.02.31.png"
        let text = Pin.prose([Pin(spot: .zero, words: "here")], about: "Screen Shot.png", at: path,
                             lettered: "A")
        #expect(text.contains("The unmarked original is at `\(path)`."))
    }

    @Test("two marked pictures in one prompt share no id")
    func twoPictures() {
        // The bug this exists to stop. Both blocks opened with the same sentence and both
        // numbered their remarks from 1, so two marked pictures pinned to one prompt arrived as
        // two markers called 1 and two items called 1 — and nothing anywhere, in the words or on
        // the pictures, said which belonged to which. A session could not resolve it, and neither
        // could a person reading over its shoulder.
        let first = [Pin(spot: .zero, words: "this badge is clipped"),
                     Pin(spot: .zero, words: "the caption wraps")]
        let second = [Pin(spot: .zero, words: "the header is the wrong weight")]
        let prompt = [Pin.prose(first, withOriginal: true, lettered: Pin.lettering(round: 0)),
                      Pin.prose(second, withOriginal: true, lettered: Pin.lettering(round: 1))]
            .joined(separator: "\n\n")

        // Every id in the prompt exactly once, and the letter is what makes that true.
        for id in ["A1", "A2", "B1"] {
            #expect(prompt.components(separatedBy: "\n\(id). ").count == 2)
        }
        // Nothing is numbered bare any more, in either block.
        #expect(!prompt.contains("\n1. "))
        #expect(!prompt.contains("\n2. "))
        // And the two headings are no longer the same sentence twice: each names the letter its
        // own markers wear, which is the one thing about the picture a session can actually see.
        #expect(prompt.contains("marked A on it:"))
        #expect(prompt.contains("marked B on it:"))
    }

    @Test("the lettering runs past Z rather than starting over")
    func lettering() {
        #expect(Pin.lettering(round: 0) == "A")
        #expect(Pin.lettering(round: 1) == "B")
        #expect(Pin.lettering(round: 25) == "Z")
        // Nobody will mark twenty-seven pictures into one prompt. A silent second A is the exact
        // bug the letters exist to stop, so there is no wrapping point.
        #expect(Pin.lettering(round: 26) == "AA")
        #expect(Pin.lettering(round: 27) == "AB")
    }
}
