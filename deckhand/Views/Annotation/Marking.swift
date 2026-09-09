import DeckhandKit
import PencilKit
import SwiftUI
import UIKit

/// The picture, and everything that can be said about it by pointing.
///
/// Tap a place and a numbered marker lands there with its keyboard already up: the number on the
/// picture and the number in the remark are the same number, which is the whole trick — it is how
/// several complaints about one screenshot stop having to be said out loud, in order, with nothing
/// to point at. Tap a marker again to fix what it says, or take it off. Switch the pencil on and
/// the picture is handed to PencilKit instead, for a circle or an arrow round something a single
/// point cannot describe.
struct Marking: View {
    let picture: UIImage
    @Binding var markup: Markup
    /// Whether the freehand layer has the touches. A mode, not a second picture.
    let pencilling: Bool
    /// Lent straight through to the remark, which is the only field on this picture.
    var say: Dictation?
    /// The place whose words are being written. A tap drops the pin and opens this straight away: a
    /// numbered marker with nothing said about it is a question nobody asked.
    @State private var writing: Pin?

    var body: some View {
        MarkedPicture(picture: picture,
                      markup: $markup,
                      pencilling: pencilling,
                      dropped: drop,
                      opened: { writing = $0 })
            .sheet(item: $writing) { pin in
                PinWords(place: place(of: pin),
                         words: said(at: pin),
                         say: say,
                         keep: { wrote($0, at: pin) },
                         drop: { remove(pin) })
            }
    }

    private func drop(at pixel: CGPoint) {
        let pin = Pin(spot: pixel)
        markup.pins.append(pin)
        writing = pin
    }

    /// The number this pin is wearing on the picture, so the sheet says the same one. Found by id:
    /// a pin compares by its words too, and the sheet is open precisely because those are about to
    /// change.
    private func place(of pin: Pin) -> Int {
        (markup.pins.firstIndex { $0.id == pin.id } ?? markup.pins.count - 1) + 1
    }

    private func said(at pin: Pin) -> String {
        markup.pins.first { $0.id == pin.id }?.words ?? ""
    }

    /// Not `say`, which is now the microphone this view lends the remark: one of the two had to
    /// give, and a method and a property of the same name reading differently is how.
    private func wrote(_ words: String, at pin: Pin) {
        guard let index = markup.pins.firstIndex(where: { $0.id == pin.id }) else { return }
        markup.pins[index].words = words
        writing = nil
    }

    /// Taken off the picture, and the rest renumbered — which happens by itself, because a pin's
    /// number is its place in the list and is not stored anywhere.
    private func remove(_ pin: Pin) {
        markup.pins.removeAll { $0.id == pin.id }
        writing = nil
    }
}

/// A picture that fits the sheet, zooms, and can be marked on.
///
/// This is UIScrollView's own job and it does the whole of it: fit on open, pinch to zoom, pan
/// inside the picture, double tap in and out, and the bounce at the edges. A SwiftUI `ScrollView`
/// was doing none of it — asked for both axes it proposes unbounded space, so `scaledToFit` had
/// nothing to fit to and a screenshot drew at its full pixel size.
struct MarkedPicture: UIViewRepresentable {
    let picture: UIImage
    @Binding var markup: Markup
    let pencilling: Bool
    /// A place was tapped that has no pin on it yet, in the picture's own pixels.
    let dropped: (CGPoint) -> Void
    let opened: (Pin) -> Void

    func makeUIView(context: Context) -> PictureScroll {
        PictureScroll(image: picture)
    }

    /// The callbacks are handed over on every pass, not once at the start: the one captured at
    /// `makeUIView` closes over the binding as it was then, and a stroke drawn ten minutes later
    /// has to land in the state as it is now.
    func updateUIView(_ view: PictureScroll, context: Context) {
        view.dropped = dropped
        view.opened = opened
        view.drew = { markup.drawing = $0 }
        view.show(picture)
        view.mark(markup)
        view.pencil(pencilling)
    }
}
