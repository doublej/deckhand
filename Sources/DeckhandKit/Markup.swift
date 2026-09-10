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
    /// The ids are the whole point: marker A3 is drawn on the picture and item A3 says what is
    /// wrong there, so the two halves of the feedback are joined by something a reader can see.
    /// A pin nobody wrote words for is still listed — it was tapped deliberately, and "look
    /// here" is a complete remark — and the original is named as well as the marked copy,
    /// because a marker sitting on top of the thing it is about hides it.
    ///
    /// `lettered` is what every marker on this picture wears in front of its number, and it is
    /// what keeps two marked pictures in one prompt apart. See `lettering(round:)`.
    ///
    /// The path is fenced in backticks so that the full stop ending the sentence cannot be read
    /// as part of it. A session handed `…/shot.png.` to `Read` is one character off a file that
    /// does not exist, and the sentence needs its full stop.
    public static func prose(_ pins: [Pin], about name: String, at path: String,
                             lettered: String) -> String {
        let original = "The unmarked original is at `\(path)`."
        // Nothing to number, so nothing to introduce: a heading over an empty list reads as a
        // list that failed to arrive. Nothing wears the letter either, so it is not mentioned.
        guard !pins.isEmpty else {
            return "Feedback drawn on the attached copy of \(name).\n\n\(original)"
        }
        let lines = ["Feedback on \(name), marked \(lettered) on the attached copy:", ""]
            + numbered(pins, lettered: lettered) + ["", original]
        return lines.joined(separator: "\n")
    }

    /// What the session reads about a picture pinned to the words rather than a file on the Mac.
    ///
    /// No path and no filename, and neither is an omission. A picture attached to the review card
    /// is bytes on the phone until Send uploads it, so there is no path to name — and the Mac
    /// renames what arrives to a timestamp, so the name this phone knows it by is one the session
    /// never sees. Either would be a sentence pointing at nothing, which is worse than no sentence:
    /// the marked copy *is* the attachment, so "the attached picture" is the whole of what can
    /// honestly be said, and the numbered markers are burnt into the very file the session opens.
    ///
    /// What it *can* honestly point at is the letter, because that is drawn on the picture too:
    /// two marked pictures in one prompt are the A one and the B one, and the session reads which
    /// is which off the markers rather than off a name nobody outside this phone ever sees.
    ///
    /// `withOriginal` where the unmarked picture went up beside the marked one. It says the two
    /// are there and nothing about which path is which, because there is no path to name and no
    /// order to promise: a session that opens both can see in a moment which one has the markers
    /// drawn on it, which is a more reliable answer than any sentence written before the upload.
    public static func prose(_ pins: [Pin], withOriginal: Bool = false,
                             lettered: String) -> String {
        // A marker sits on top of the thing it is about, so the unmarked copy is not a spare —
        // it is the only view of whatever marker 3 is covering.
        let both = "Both copies are attached: the one with the marks on it, and the same picture "
            + "unmarked, for wherever a marker covers what it is about."
        guard !pins.isEmpty else {
            let alone = "Feedback drawn on the attached picture."
            return withOriginal ? "\(alone)\n\n\(both)" : alone
        }
        let lines = ["Feedback on the attached picture, marked \(lettered) on it:", ""]
            + numbered(pins, lettered: lettered)
        return (withOriginal ? lines + ["", both] : lines).joined(separator: "\n")
    }

    /// The remarks, lettered by which picture they are about and numbered by where their markers
    /// are in the list. Shared by both, because an id that disagreed between a file's feedback and
    /// an attachment's would be the one bug neither could be read through.
    private static func numbered(_ pins: [Pin], lettered: String) -> [String] {
        pins.enumerated().map { number, pin in
            let words = pin.words.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(lettered)\(number + 1). \(words.isEmpty ? "look here" : words)"
        }
    }

    /// What the markers of one round of marking wear in front of their numbers: A, B, … Z, AA.
    ///
    /// Two pictures marked up into one prompt used to arrive with two markers called 1, two items
    /// called 1, and nothing anywhere saying which belonged to which — the session could not
    /// resolve it and neither could anybody reading over its shoulder. A letter per picture is
    /// what fits the one hard constraint here: the marker is burnt into the picture's pixels, so
    /// an id has to be drawable in a small disc *and* appear identically in the words.
    ///
    /// A letter rather than carrying on counting across the prompt, because taking one picture
    /// out then renumbers every remark about the others — including the ones already burnt into
    /// their pixels, which cannot be renumbered at all.
    ///
    /// Bijective base 26, so the twenty-seventh round is AA and never a second A. Nobody will
    /// mark up twenty-seven pictures in one prompt; a silent repeat is the exact bug this exists
    /// to stop, and refusing to have a wrapping point costs four lines.
    public static func lettering(round: Int) -> String {
        var left = max(0, round)
        var letters = ""
        repeat {
            letters = String(UnicodeScalar(UInt8(65 + left % 26))) + letters
            left = left / 26 - 1
        } while left >= 0
        return letters
    }
}
