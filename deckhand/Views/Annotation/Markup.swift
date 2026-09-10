import DeckhandKit
import PencilKit
import SwiftUI
import UIKit

/// Everything marked on one picture: the places, in the order they were tapped, and whatever was
/// drawn freehand over the top.
///
/// Both halves are kept in the picture's own pixels, which is the only space that survives the
/// sheet being resized or turned. In the app target rather than in DeckhandKit because of
/// `PKDrawing` — PencilKit is an iOS framework and the package has to build for the Mac. `Pin`
/// itself is over there, where it can be tested.
struct Markup: Equatable {
    var pins: [Pin] = []
    var drawing = PKDrawing()

    /// Nothing has been marked. The unmarked picture is already on the Mac, so offering to hand it
    /// back with nothing on it is offering to say nothing at all.
    var isEmpty: Bool { pins.isEmpty && drawing.strokes.isEmpty }
}

/// The picture with the drawing and the numbered markers burnt in, at the picture's full size.
///
/// Full size and explicitly at scale 1: this becomes a PNG a session reads off disk, and a 3×
/// render of a 400pt view is a blurry quarter of the screenshot he marked up. Everything is
/// measured off the image's own dimensions for the same reason — a marker sized for the phone's
/// screen is a dozen pixels on a Retina screenshot, which is a speck nobody will find.
///
/// The drawing needs no scaling here because it is already kept in pixels; see `PictureScroll`,
/// which is where the conversion happens, once, as the strokes come off the canvas.
func flattened(_ markup: Markup, onto picture: UIImage) -> UIImage {
    let size = pixelSize(of: picture)
    let whole = CGRect(origin: .zero, size: size)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { pass in
        picture.draw(in: whole)
        if !markup.drawing.strokes.isEmpty {
            markup.drawing.image(from: whole, scale: 1).draw(in: whole)
        }
        for (place, pin) in markup.pins.enumerated() {
            draw(place + 1, at: pin.spot, on: pass.cgContext, across: size)
        }
    }
}

/// The picture's real pixels, not its points. A file fetched off the Mac is at scale 1 and the two
/// are the same number; anything the phone made itself is not, and working in points there would
/// quietly throw away half the resolution and put every pin at half its distance.
func pixelSize(of picture: UIImage) -> CGSize {
    guard let raw = picture.cgImage else {
        return CGSize(width: picture.size.width * picture.scale,
                      height: picture.size.height * picture.scale)
    }
    return CGSize(width: raw.width, height: raw.height)
}

/// How big a numbered marker is, in both of the two places one gets drawn.
enum Marker {
    /// On screen, a constant. A marker that zoomed with the picture would be three points across
    /// at fit — unreadable — and a third of the sheet at 12×, covering the thing it points at. So
    /// the markers live outside the view the zoom transforms, and `PictureScroll.place()` puts
    /// them back on their spots every time the zoom changes.
    static let onScreen: CGFloat = 26

    /// On the picture, a fraction of its shorter side, so it reads the same on a phone screenshot
    /// as on a 6K one.
    static func width(across size: CGSize) -> CGFloat {
        max(onScreen, min(size.width, size.height) * 0.045)
    }

    /// How big the numeral is against the disc it sits in. Heavy at this size, because the figure
    /// is the whole of what the marker says and a screenshot is usually busy behind it.
    static let figure: CGFloat = 0.56

    /// The three discs, outside in: a white ring, a black ring, and the white face the numeral is
    /// drawn on. Fractions of the width rather than fixed points, so the marker looks like the
    /// same object at 26 points on screen and at 90 pixels on a 6K screenshot.
    static func bands(across wide: CGFloat) -> [(UIColor, CGFloat)] {
        [(.white, 0), (.black, wide * 0.07), (.white, wide * 0.20)]
    }

    /// The same marker as a view, for while the picture is still being marked up. One label
    /// carries one border, so the black ring is the border and the white ring outside it is a
    /// shadow with no blur and no offset — which is also why `clipsToBounds` stays off. There is
    /// nothing inside to clip: the figure is centred and fits.
    static func label() -> UILabel {
        let marker = UILabel(frame: CGRect(x: 0, y: 0, width: onScreen, height: onScreen))
        marker.textAlignment = .center
        marker.font = .systemFont(ofSize: onScreen * figure, weight: .heavy)
        marker.textColor = .black
        marker.backgroundColor = .white
        marker.layer.cornerRadius = onScreen / 2
        marker.layer.borderColor = UIColor.black.cgColor
        marker.layer.shadowColor = UIColor.white.cgColor
        marker.layer.shadowOpacity = 1
        marker.layer.shadowRadius = 0
        marker.layer.shadowOffset = .zero
        marker.layer.shadowPath = UIBezierPath(
            ovalIn: marker.bounds.insetBy(dx: -onScreen * 0.07, dy: -onScreen * 0.07)
        ).cgPath
        return marker
    }

    /// A thicker ring and a touch larger when it is the chosen one. Never a different colour: the
    /// two rings are structural — they are what holds the marker off whatever is behind it — and
    /// a chosen marker that changed colour would read as a second kind of mark.
    static func dress(_ marker: UILabel, chosen: Bool) {
        marker.layer.borderWidth = onScreen * (chosen ? 0.13 : 0.09)
        marker.transform = chosen ? CGAffineTransform(scaleX: 1.18, y: 1.18) : .identity
    }
}

/// A numeral in a disc, drawn to be read off anything.
///
/// Deliberately not in this app's colours. Everywhere else a mark is teal because teal is what
/// says "Deckhand"; here it is drawn *over somebody else's picture*, and the picture is very
/// often a screenshot of this app — a teal disc on a teal button is a marker you have to hunt
/// for, which is the one thing a marker may not be.
///
/// So it carries no hue at all: black figure on a white face, a black ring around it, and a white
/// ring around that. Two rings rather than one because a single ring can only separate the marker
/// from one kind of background — the white one holds it off a dark picture, the black one off a
/// light one, and between them there is no colour a photograph or a screenshot can be that the
/// marker disappears into. Black on white is also the most legible a numeral gets, which matters
/// at a fifth of the size on a 6K screenshot.
private func draw(_ number: Int, at pixel: CGPoint, on context: CGContext, across size: CGSize) {
    let wide = Marker.width(across: size)
    let disc = CGRect(x: pixel.x - wide / 2, y: pixel.y - wide / 2, width: wide, height: wide)
    // Nested fills rather than strokes: a stroke straddles its path, so two of them at different
    // widths need their insets worked out from half of each. Three discs cannot be misaligned.
    for (colour, inset) in Marker.bands(across: wide) {
        context.setFillColor(colour.cgColor)
        context.fillEllipse(in: disc.insetBy(dx: inset, dy: inset))
    }
    let style: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: wide * Marker.figure, weight: .heavy),
        .foregroundColor: UIColor.black
    ]
    let figure = "\(number)" as NSString
    let box = figure.size(withAttributes: style)
    figure.draw(at: CGPoint(x: disc.midX - box.width / 2, y: disc.midY - box.height / 2),
                withAttributes: style)
}
