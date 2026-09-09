import CoreGraphics

// Where a point on the screen lands on a picture, and where a point on the picture lands back on
// the screen. Here rather than in the app target for the same reason `Markup` is: this is the part
// with no UIKit in it, and it is the part that goes wrong.

/// A picture is never drawn at its own size. It is fitted to the sheet, and then multiplied again
/// by whatever has been pinched. A mark is kept in the picture's own pixels — the only space that
/// still means anything once the sheet has been rotated or the zoom thrown away — so every tap has
/// to be divided by that fraction and every marker multiplied back by it.
///
/// This is the one piece of arithmetic in the markup that fails silently: a pin landing a few
/// percent off still looks deliberate, and ends up pointing at the word next to the wrong one.
/// Hence a pure function, no UIKit, and a test.
public enum Fitting {
    /// How much a picture has to shrink to sit inside `box` whole, keeping its aspect. Above 1
    /// where the box is the larger of the two, which a small screenshot on a full sheet is.
    public static func scale(of picture: CGSize, into box: CGSize) -> CGFloat {
        guard picture.width > 0, picture.height > 0 else { return 1 }
        return min(box.width / picture.width, box.height / picture.height)
    }

    /// The pixel of `picture` under a point measured in whatever space `drawn` is measured in, or
    /// nil where the point missed the picture altogether. The letterboxing around a fitted
    /// screenshot is most of the sheet, and a tap out there means nothing.
    public static func pixel(at point: CGPoint, of picture: CGSize, drawn: CGRect) -> CGPoint? {
        guard drawn.width > 0, drawn.height > 0, drawn.contains(point) else { return nil }
        return CGPoint(x: (point.x - drawn.minX) * picture.width / drawn.width,
                       y: (point.y - drawn.minY) * picture.height / drawn.height)
    }

    /// Where a pixel of `picture` sits inside `drawn`. The inverse of `pixel(at:of:drawn:)`, and
    /// what puts a marker back on its spot after a pinch.
    public static func point(of pixel: CGPoint, of picture: CGSize, drawn: CGRect) -> CGPoint {
        guard picture.width > 0, picture.height > 0 else { return drawn.origin }
        return CGPoint(x: drawn.minX + pixel.x * drawn.width / picture.width,
                       y: drawn.minY + pixel.y * drawn.height / picture.height)
    }
}
