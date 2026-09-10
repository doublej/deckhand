import DeckhandKit
import SwiftUI

/// The rail and the manager, side by side, with the screen sliding between them.
///
/// **Why a shell and not a `TabView(.page)`.** The rail is a `List` and every row on it already
/// spends its horizontal drag on `swipeActions` — star on one edge, hide on the other. Paging a
/// `TabView` is a UIKit pan inside the view, so wrapping the rail in one puts that pan against
/// every row's swipe, which is the same arbitration fight `SessionView`'s back gesture had to
/// win and worse: there it was one 20pt margin, here it would be the whole page.
///
/// So the gesture lives where it cannot collide. A 24pt clear strip is **overlaid on** the
/// trailing edge — drawn over the rows, so it takes the touch before the `List` sees it, exactly
/// as `SessionView.back` takes it before the pane pan — and while it is dragged the whole screen
/// follows the finger. The price is the same price that one paid: the trailing 24pt of a row no
/// longer reveals its swipe actions. The rest of the row still does.
///
/// The panel opens the other way too, from the glyph in `RailFoot`. A gesture nobody is told
/// about is not a way in for somebody using VoiceOver.
struct ManagerShell<Content: View>: View {
    @Bindable var model: AppModel
    @ViewBuilder let content: () -> Content

    /// How far the finger has taken the screen, added to wherever it already was. Zero at rest.
    @State private var drag: CGFloat = 0
    @Environment(\.layoutDirection) private var direction

    /// The width of the strip a drag may start in. Wide enough to hit without aiming, narrow
    /// enough to leave a row's swipe actions reachable. A computed property rather than a
    /// `static let`, which a generic type may not have.
    private var edge: CGFloat { 24 }

    /// Which way the screen moves. `HStack` already lays its children out right-to-left in a
    /// right-to-left reading, so revealing the second one means moving the stack the other way —
    /// the sign is the whole of the difference and there is no second code path.
    private var sign: CGFloat { direction == .rightToLeft ? -1 : 1 }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            HStack(spacing: 0) {
                content()
                    .frame(width: width)
                    .overlay(alignment: .trailing) { strip(width) }
                    // Nothing behind the panel is reachable while it is open: it is off the
                    // screen, and a stray touch landing on a row you cannot see is worse than
                    // no touch at all.
                    .disabled(model.manager.open)
                ManagerView(model: model)
                    .frame(width: width)
                    .overlay(alignment: .leading) { strip(width) }
            }
            .frame(width: width * 2, alignment: .leading)
            .offset(x: sign * offset(width))
        }
    }

    /// Where the pair sits: at rest, one screen either way; mid-drag, wherever the finger is.
    private func offset(_ width: CGFloat) -> CGFloat {
        let settled: CGFloat = model.manager.open ? -width : 0
        return min(0, max(-width, settled + drag))
    }

    /// The strip that owns the gesture. Clear, so it is invisible; drawn over what is under it,
    /// so it is the thing the touch reaches first.
    private func strip(_ width: CGFloat) -> some View {
        Color.clear
            .frame(width: edge)
            .contentShape(Rectangle())
            .gesture(
                // A real minimum distance, or a tap on a row near the trailing edge becomes a
                // one-pixel drag and the strip eats it.
                DragGesture(minimumDistance: 20, coordinateSpace: .global)
                    .onChanged { drag = sign * $0.translation.width }
                    .onEnded { settle($0, width) }
            )
    }

    /// Open or closed, decided on where it was let go *and* where it was going. A flick that
    /// covered a third of the screen means the same thing as a slow drag across most of it.
    private func settle(_ gesture: DragGesture.Value, _ width: CGFloat) {
        let moved = sign * gesture.translation.width
        let thrown = sign * gesture.predictedEndTranslation.width
        let far = abs(moved) > width / 3 || abs(thrown) > width / 2
        let opening = moved < 0
        withAnimation(Motion.opening) {
            if far { model.manager.open = opening }
            drag = 0
        }
    }
}
