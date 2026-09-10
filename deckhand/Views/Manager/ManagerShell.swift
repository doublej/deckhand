import DeckhandKit
import SwiftUI

/// The rail and the manager, side by side, with the screen sliding between them.
///
/// **Why a shell and not a `TabView(.page)`.** Paging a `TabView` is a UIKit pan inside the view,
/// and the rail is a `List`: that pan would run against every row's own gestures with no say in
/// which drags it answers to. This needs the say.
///
/// **Why the whole screen and not a strip at the edge of it.** It was a 24pt clear strip overlaid
/// on the trailing edge, taking the touch before the `List` could see it. That works and it is
/// 24 points wide, which means aiming at an edge to reach a screen — and it cost that strip its
/// vertical scrolling, the same price `SessionView.back` pays for its 20. Widening a strip only
/// makes both worse: a bigger patch of dead scrolling, still a patch.
///
/// So it takes the touch from nothing at all. `simultaneousGesture` **watches** every drag on the
/// screen without claiming any of them — the rail scrolls, a row opens on a tap, a row talks on a
/// hold, all exactly as before — and this moves the screen for one shape of drag: sideways rather
/// than up the page, and going the one way there is something to reveal. Every row action lives
/// on the leading edge now (`SessionListView.row`), so a leading-going drag is the row's and this
/// never answers to one. What is left is a gesture the rail has no use for, which is what lets it
/// be the whole screen.
///
/// It stands down entirely while a session's page is up (`ManagerDesk.covered`). This shell wraps
/// the whole app, so without that it was a *third* meaning for a sideways drag on a screen that
/// already has two — it took `SessionView`'s pane paging and the leading-edge way out with it.
///
/// The panel opens the other way too, from the glyph in `RailFoot`. A gesture nobody is told
/// about is not a way in for somebody using VoiceOver.
struct ManagerShell<Content: View>: View {
    @Bindable var model: AppModel
    @ViewBuilder let content: () -> Content

    /// How far the finger has taken the screen, added to wherever it already was. Zero at rest.
    @State private var drag: CGFloat = 0
    @Environment(\.layoutDirection) private var direction

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
                    // Nothing behind the panel is reachable while it is open: it is off the
                    // screen, and a stray touch landing on a row you cannot see is worse than
                    // no touch at all.
                    .disabled(model.manager.open)
                ManagerView(model: model)
                    .frame(width: width)
            }
            .frame(width: width * 2, alignment: .leading)
            .offset(x: sign * offset(width))
            .simultaneousGesture(slide(width))
        }
    }

    /// Where the pair sits: at rest, one screen either way; mid-drag, wherever the finger is.
    private func offset(_ width: CGFloat) -> CGFloat {
        let settled: CGFloat = model.manager.open ? -width : 0
        return min(0, max(-width, settled + drag))
    }

    /// The drag that moves the screen, watched for anywhere on it.
    ///
    /// A real minimum distance, or a tap becomes a one-pixel drag and the screen twitches under
    /// every touch.
    private func slide(_ width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onChanged { value in
                guard mine(value) else { return }
                drag = sign * value.translation.width
            }
            // Whatever this turned into by the time the finger left, a drag this one has already
            // moved the screen for is this one's to put down. Asking `mine` again here is how the
            // screen ends up parked halfway: swipe out, change your mind, come back, let go.
            .onEnded { value in
                guard drag != 0 else { return }
                settle(value, width)
            }
    }

    /// Whether this drag is the one that moves the screen: sideways rather than up the page, and
    /// pointing the only way there is anything to reveal.
    ///
    /// This is the whole of what keeps the rail's own gestures intact, and it is why nothing here
    /// has to win an arbitration fight. A drag up or down the page is the list's. A leading-going
    /// drag is the row's — every row action lives on that edge. This answers to neither.
    private func mine(_ value: DragGesture.Value) -> Bool {
        guard !model.manager.covered else { return false }
        let sideways = sign * value.translation.width
        guard abs(sideways) > abs(value.translation.height) else { return false }
        return model.manager.open ? sideways > 0 : sideways < 0
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
