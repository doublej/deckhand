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
        #expect(Pin.prose(pins, about: "shot.png", at: "/Users/jj/dev/shot.png") == """
            Feedback on shot.png, marked on the attached copy:

            1. this badge is clipped
            2. the caption wraps onto four lines
            3. too much air under the footer

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
        let text = Pin.prose(pins, about: "a.png", at: "/a.png")
        #expect(text.contains("1. the header is the wrong weight"))
        #expect(text.contains("2. look here"))
        // Whitespace is nothing typed, not a remark made of spaces.
        #expect(text.contains("3. look here"))
    }

    @Test("the numbers follow the order the places were marked, not where they are")
    func order() {
        // Marked bottom-right first, top-left second. Sorted by position these would swap, and
        // then marker 1 on the picture would point at the second thing in the words.
        let pins = [
            Pin(spot: CGPoint(x: 900, y: 1400), words: "this one was marked first"),
            Pin(spot: CGPoint(x: 4, y: 8), words: "this one second")
        ]
        let text = Pin.prose(pins, about: "a.png", at: "/a.png")
        #expect(text.contains("1. this one was marked first\n2. this one second"))
    }

    @Test("a picture with only a drawing on it still names both copies")
    func drawnOnly() {
        let text = Pin.prose([], about: "chart.jpeg", at: "/tmp/chart.jpeg")
        #expect(text.hasPrefix("Feedback drawn on the attached copy of chart.jpeg."))
        #expect(text.hasSuffix("The unmarked original is at `/tmp/chart.jpeg`."))
        // No list at all rather than an empty one introduced as though it had items in it.
        #expect(!text.contains("1."))
    }

    @Test("the original's path is carried exactly as it came")
    func spacedPath() {
        // What a Mac screenshot is really called. The path is the session's way back to the
        // unmarked picture, so a prose line that tidied the spaces out of it would be a dead end.
        let path = "/Users/jj/Desktop/Screen Shot 2026-09-10 at 11.02.31.png"
        let text = Pin.prose([Pin(spot: .zero, words: "here")], about: "Screen Shot.png", at: path)
        #expect(text.contains("The unmarked original is at `\(path)`."))
    }
}
