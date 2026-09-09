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
}

/// A numeral in a filled disc: the tint, a white figure, and a hairline ring so it still separates
/// from the picture when what is underneath happens to be teal. Not the capsule-round-a-label shape
/// this app has banned — there is nothing to press and nothing but the number inside it.
private func draw(_ number: Int, at pixel: CGPoint, on context: CGContext, across size: CGSize) {
    let wide = Marker.width(across: size)
    let disc = CGRect(x: pixel.x - wide / 2, y: pixel.y - wide / 2, width: wide, height: wide)
    context.setFillColor(UIColor(Palette.tint).cgColor)
    context.fillEllipse(in: disc)
    context.setStrokeColor(UIColor.white.cgColor)
    context.setLineWidth(max(1, wide / 16))
    context.strokeEllipse(in: disc)
    let style: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: wide * 0.58, weight: .semibold),
        .foregroundColor: UIColor.white
    ]
    let figure = "\(number)" as NSString
    let box = figure.size(withAttributes: style)
    figure.draw(at: CGPoint(x: disc.midX - box.width / 2, y: disc.midY - box.height / 2),
                withAttributes: style)
}
