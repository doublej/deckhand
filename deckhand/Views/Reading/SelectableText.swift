import SwiftUI
import UIKit

/// Text you can run a finger through and take one sentence out of.
///
/// `.textSelection(.enabled)` is not this. On iOS it gives a `Text` one gesture with one meaning
/// — select the whole view and offer Copy — with no handles and no way to take a line out of a
/// page. That is what "I can only copy the entire thing" was: the modifier was already on the
/// turn and on the file source, and it was doing exactly what it does. Range selection on this
/// floor is a `UITextView` and nothing else: it owns the handles, the loupe, Select All and the
/// same menu every other app on the phone has.
///
/// Not editable and never first responder on its own, so no keyboard arrives — this is a page
/// to read, not a field. No colour is set either: `UITextView` draws in `.label`, which is
/// `Palette.textPrimary` (`Color.primary`) already, so it follows the surface the way a `Text`
/// would rather than freezing one appearance at the moment the view was made.
///
/// It scrolls itself. A `UITextView` sized to its content inside a SwiftUI `ScrollView` needs the
/// height posted back the way `MermaidBlock` posts a diagram's, and here there is nothing to gain
/// from it: both callers hand this the whole screen.
struct SelectableText: UIViewRepresentable {
    let text: String
    /// The face to read it in. A turn is prose and a file's source is code, and the caller is the
    /// only one that knows which — spelled as a `UIFont` because this side of the seam is UIKit,
    /// and matched to ``Typography`` by the caller rather than converted here.
    let font: UIFont

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.backgroundColor = .clear
        // The caller has already padded this; the text container must not inset it again.
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        // A turn is full of paths and flags that are not addresses. `Links` marks the real ones
        // where a turn is *read*; here the whole point is that a press selects rather than opens.
        view.dataDetectorTypes = []
        view.alwaysBounceVertical = true
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.font = font
        // Guarded: assigning `text` clears the selection, so a redraw for any other reason would
        // take the passage out of somebody's fingers mid-drag.
        if view.text != text { view.text = text }
    }
}
