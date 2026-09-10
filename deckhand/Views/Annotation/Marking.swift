import DeckhandKit
import PencilKit
import SwiftUI
import UIKit

/// The picture, and everything that can be said about it by pointing.
///
/// Tap a place and a numbered marker lands there, chosen: the number on the picture and the number
/// in the remark are the same number, which is the whole trick — it is how several complaints about
/// one screenshot stop having to be said out loud, in order, with nothing to point at. The chosen
/// marker grows its controls beside it, so the picture stays in view while you say what is wrong
/// with it. Tap a marker to choose it, and again to put the controls away.
/// Switch the pencil on and the picture is handed to PencilKit instead, for a circle or an arrow
/// round something a single point cannot describe.
///
/// The controls used to be a full-height sheet with a field in it. Two things were wrong with that
/// and both were the same thing: it hid the picture the remark is about, and it led with a box to
/// type in. `PinCallout` has no field at all.
struct Marking: View {
    let picture: UIImage
    @Binding var markup: Markup
    /// Whether the freehand layer has the touches. A mode, not a second picture.
    let pencilling: Bool
    /// Lent straight through to the callout, which is the only thing on this picture that records.
    var say: Dictation?
    /// The place whose controls are showing. An id rather than a `Pin`, because a pin compares by
    /// its words as well and those are exactly what is about to change.
    @State private var chosen: Pin.ID?
    /// Where that marker is on screen, as the scroll view last put it. Not the pin's own spot,
    /// which is in the picture's pixels and says nothing about where the picture currently is.
    @State private var onScreen: CGPoint?
    /// How tall the controls came out. Measured rather than guessed, because it decides whether
    /// they go above the marker or below it.
    @State private var high: CGFloat = 0

    /// Clear of the marker, which is `Marker.onScreen` across and centred on its spot.
    private static let gap: CGFloat = 22

    var body: some View {
        MarkedPicture(picture: picture,
                      markup: $markup,
                      pencilling: pencilling,
                      chosen: chosen,
                      dropped: drop,
                      opened: choose,
                      moved: { onScreen = $0 })
            .overlay { controls }
            // A pin cannot be chosen while the pencil has the touches, and a callout left over
            // from before the switch would sit over the drawing taking taps meant for it.
            .onChange(of: pencilling) { chosen = nil }
    }

    /// Beside the marker, inside the picture's own bounds. A `GeometryReader` in an overlay reads
    /// the size of what it is over and lays out nothing of its own, so this costs the picture
    /// underneath nothing.
    @ViewBuilder private var controls: some View {
        GeometryReader { box in
            if let pin = selected, let spot = onScreen {
                PinCallout(place: place(of: pin),
                           words: pin.words,
                           say: say,
                           heard: { await wrote($0, at: pin) },
                           drop: { remove(pin) })
                    .frame(width: min(PinCallout.wide, box.size.width - Spacing.medium * 2))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { high = $0 }
                    .offset(x: sideways(spot, in: box.size), y: upright(spot, in: box.size))
                    .animation(.easeOut(duration: 0.12), value: spot)
            }
        }
    }

    private var selected: Pin? {
        chosen.flatMap { id in markup.pins.first { $0.id == id } }
    }

    /// Centred on the marker where it fits, and shouldered off the edge where it does not — never
    /// hanging over it, because the half outside the picture is the half holding the microphone.
    private func sideways(_ spot: CGPoint, in size: CGSize) -> CGFloat {
        let wide = min(PinCallout.wide, size.width - Spacing.medium * 2)
        let want = spot.x - wide / 2
        return min(max(Spacing.medium, want), max(Spacing.medium, size.width - wide - Spacing.medium))
    }

    /// Below the marker, or above it when there is no room below. Decided by the measured height
    /// rather than by where the marker is in the picture: the same marker needs one answer with a
    /// line of words under it and the other with three.
    private func upright(_ spot: CGPoint, in size: CGSize) -> CGFloat {
        let below = spot.y + Self.gap
        if below + high <= size.height - Spacing.small { return below }
        return max(Spacing.small, spot.y - Self.gap - high)
    }

    /// A tap on the picture is always a new place, chosen — one tap per place, however many are
    /// already on it.
    ///
    /// Dismissing on a tap instead was the obvious reading and it is wrong here, because of how the
    /// taps are arbitrated: the single tap waits for the double tap to fail, so dismiss-then-drop is
    /// two taps in one spot in quick succession, which *is* a double tap — and a double tap zooms.
    /// Marking three places on a screenshot would have zoomed twice. The chosen marker is the way
    /// out instead, and it is a 26pt target with a marker's width of reach around it.
    private func drop(at pixel: CGPoint) {
        let pin = Pin(spot: pixel)
        markup.pins.append(pin)
        chosen = pin.id
    }

    /// A tap on a marker: choose it, or put its controls away if it was already the chosen one.
    /// This is the only way to close a callout without answering it, which is why it is a toggle.
    private func choose(_ pin: Pin) {
        chosen = chosen == pin.id ? nil : pin.id
    }

    /// The number this pin is wearing on the picture, so the callout says the same one. Found by
    /// id, for the same reason `chosen` is an id.
    private func place(of pin: Pin) -> Int {
        (markup.pins.firstIndex { $0.id == pin.id } ?? markup.pins.count - 1) + 1
    }

    /// Over what was there, not after it. A remark said twice at one place is a remark corrected —
    /// this is the one dictation in the app that deliberately does not call `Underneath.words`.
    private func wrote(_ words: String, at pin: Pin) async {
        guard let index = markup.pins.firstIndex(where: { $0.id == pin.id }) else { return }
        markup.pins[index].words = words
    }

    /// Taken off the picture, and the rest renumbered — which happens by itself, because a pin's
    /// number is its place in the list and is not stored anywhere.
    private func remove(_ pin: Pin) {
        markup.pins.removeAll { $0.id == pin.id }
        chosen = nil
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
    /// Which marker wears the chosen ring.
    let chosen: Pin.ID?
    /// A place was tapped that has no pin on it yet, in the picture's own pixels.
    let dropped: (CGPoint) -> Void
    let opened: (Pin) -> Void
    /// Where the chosen marker now is, in this view's own space. Nil when nothing is chosen.
    let moved: (CGPoint?) -> Void

    func makeUIView(context: Context) -> PictureScroll {
        PictureScroll(image: picture)
    }

    /// The callbacks are handed over on every pass, not once at the start: the one captured at
    /// `makeUIView` closes over the binding as it was then, and a stroke drawn ten minutes later
    /// has to land in the state as it is now.
    ///
    /// `moved` goes in before `chosen`, because setting `chosen` is what reports a position and a
    /// closure assigned after that report is a callout that never appears.
    func updateUIView(_ view: PictureScroll, context: Context) {
        view.dropped = dropped
        view.opened = opened
        view.moved = moved
        view.drew = { markup.drawing = $0 }
        view.show(picture)
        view.mark(markup)
        view.choose(chosen)
        view.pencil(pencilling)
    }
}
