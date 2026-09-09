import CoreGraphics
import Foundation

// What was marked on a picture, and what the session is told about it. Here rather than in the
// app target because this is the part with no UIKit in it, which is the part worth testing.

/// One place on a picture, and what is wrong there.
///
/// `spot` is in the image's own pixel space, not the screen's. The picture is fitted, zoomed and
/// panned while it is being marked up, so a point in view coordinates means nothing a moment
/// later — and the flattened copy is drawn at full size, where only pixels are meaningful.
public struct Pin: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var spot: CGPoint
    public var words: String

    public init(id: UUID = UUID(), spot: CGPoint, words: String = "") {
        self.id = id
        self.spot = spot
        self.words = words
    }

    /// What the session reads, in the order the places were marked.
    ///
    /// The numbers are the whole point: marker 3 is drawn on the picture and item 3 says what is
    /// wrong there, so the two halves of the feedback are joined by something a reader can see.
    /// A pin nobody wrote words for is still listed — it was tapped deliberately, and "look
    /// here" is a complete remark — and the original is named as well as the marked copy,
    /// because a marker sitting on top of the thing it is about hides it.
    ///
    /// The path is fenced in backticks so that the full stop ending the sentence cannot be read
    /// as part of it. A session handed `…/shot.png.` to `Read` is one character off a file that
    /// does not exist, and the sentence needs its full stop.
    public static func prose(_ pins: [Pin], about name: String, at path: String) -> String {
        let original = "The unmarked original is at `\(path)`."
        // Nothing to number, so nothing to introduce: a heading over an empty list reads as a
        // list that failed to arrive.
        guard !pins.isEmpty else {
            return "Feedback drawn on the attached copy of \(name).\n\n\(original)"
        }
        var lines = ["Feedback on \(name), marked on the attached copy:", ""]
        for (number, pin) in pins.enumerated() {
            let words = pin.words.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("\(number + 1). \(words.isEmpty ? "look here" : words)")
        }
        lines.append(contentsOf: ["", original])
        return lines.joined(separator: "\n")
    }
}
