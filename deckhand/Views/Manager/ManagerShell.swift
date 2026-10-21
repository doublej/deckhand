import DeckhandKit
import SwiftUI

/// The manager as a drawer: pulled in over whatever screen is up, and put back to leave it
/// exactly where it was.
///
/// It was a screen of its own, the rail's neighbour, which meant reaching it from a session took
/// three moves — out, across, and a tap on its tab — and it was off entirely while a session's
/// page was up. A drawer is reached from anywhere and costs nothing to leave.
///
/// **Two ways in, and a handle is the one that is everywhere.** A small pill sits on the trailing
/// edge of every screen; tap it or drag it in. On the rail the whole screen also answers a
/// trailing-going sideways drag, as it always has: `simultaneousGesture` **watches** every drag
/// without claiming any — the rail scrolls, a row opens on a tap and talks on a hold, exactly as
/// before — and moves the drawer for that one shape. Every row action lives on the leading edge
/// (`SessionListView.row`), so a leading-going drag is the row's and this never answers to one.
/// On a session's page (`ManagerDesk.covered`) that whole-screen swipe stands down: a sideways
/// drag there already pages the panes and a leading one leaves, so only the handle opens it.
///
/// **Out** is the dimmed strip left showing, or a trailing-going drag on the drawer itself — the
/// way it came in, reversed.
///
/// The handle is a strip of touch the size of a thumb, not an edge: a clear strip down the whole
/// edge costs its width in vertical scrolling, the price `SessionView.back` pays for its 20.
struct ManagerShell<Content: View>: View {
    @Bindable var model: AppModel
    @ViewBuilder let content: () -> Content

    /// How far the finger has pulled the drawer, added to wherever it already was: positive is
    /// further in. Zero at rest.
    @State private var drag: CGFloat = 0
    @Environment(\.layoutDirection) private var direction

    /// What of the screen behind stays showing, dimmed, as the place to tap to put it back.
    private var margin: CGFloat { 44 }
    /// Computed rather than `static let`, which a generic type may not have.
    /// Wider than this and a line of the conversation is too long to read; a phone on its side is.
    private var widest: CGFloat { 480 }

    private var desk: ManagerDesk { model.manager }

    /// Which way is "in". `layoutDirection` rather than a constant, so the drawer comes from the
    /// trailing edge in a right-to-left reading too; the sign is the whole of the difference.
    private var sign: CGFloat { direction == .rightToLeft ? -1 : 1 }

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width - margin, widest)
            let shown = revealed(width)
            ZStack(alignment: .trailing) {
                content()
                    // Nothing behind the drawer is reachable while it is in: a stray touch on a
                    // row you can barely see is worse than no touch at all.
                    .disabled(desk.open)
                    .accessibilityHidden(desk.open)
                    .simultaneousGesture(swipe(width))
                scrim(shown / width)
                drawer(width, shown: shown)
                handle(width)
                    .opacity(shown > 0 ? 0 : 1)
            }
        }
        // While it is closed, a slow look at the conversation — `watching: false`, so the Mac
        // still pushes — keeps the handle's unread dot true. Open, `ManagerView` polls itself.
        .task(id: desk.open) {
            while !Task.isCancelled && !desk.open {
                await model.pollManager(watching: false)
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    /// What is left of the screen behind, dimmed as far as the drawer is in, and the place to tap
    /// to put it back.
    private func scrim(_ fraction: CGFloat) -> some View {
        Color.black
            .opacity(0.45 * fraction)
            .ignoresSafeArea()
            .allowsHitTesting(desk.open)
            .onTapGesture { settle(open: false) }
            .accessibilityHidden(true)
    }

    private func drawer(_ width: CGFloat, shown: CGFloat) -> some View {
        ManagerView(model: model)
            .frame(width: width)
            .shadow(color: .black.opacity(shown > 0 ? 0.3 : 0), radius: 12)
            // Out past the trailing edge by however much is not yet pulled in, and the shadow's
            // width further when closed so none of it shows.
            .offset(x: sign * (width - shown + (shown > 0 ? 0 : 24)))
            .disabled(!desk.open)
            .accessibilityHidden(!desk.open)
            .simultaneousGesture(swipe(width))
    }

    /// How much of the drawer is in: all of it at rest when open, none when closed, and wherever
    /// the finger is in between.
    private func revealed(_ width: CGFloat) -> CGFloat {
        min(width, max(0, (desk.open ? width : 0) + drag))
    }

    /// The pill on the trailing edge, and the count of slips waiting across the rail beside it so
    /// it says why to pull. A dot when the manager has said something you have not read.
    private func handle(_ width: CGFloat) -> some View {
        pill
            .padding(.trailing, 3)
            .frame(width: 32, height: 104, alignment: .trailing)
            .contentShape(Rectangle())
            .onTapGesture { settle(open: true) }
            .gesture(pull(width))
            .accessibilityElement()
            .accessibilityLabel("Manager")
            .accessibilityValue(waiting > 0 ? "\(waiting) waiting" : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { settle(open: true) }
            .accessibilityIdentifier("manager-handle")
            .allowsHitTesting(!desk.open)
    }

    private var pill: some View {
        HStack(spacing: Spacing.xxs) {
            if waiting > 0 {
                Text("\(waiting)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.lcdYellow)
            }
            VStack(spacing: Spacing.xxs) {
                Circle()
                    .fill(Palette.tint)
                    .frame(width: 6, height: 6)
                    .opacity(desk.unread ? 1 : 0)
                Capsule()
                    .fill(Palette.tint.opacity(0.7))
                    .frame(width: 5, height: 52)
            }
        }
    }

    private var waiting: Int { model.visibleSessions.reduce(0) { $0 + $1.waitingPages } }

    /// The handle's own drag: it follows the finger from the first point, wherever it goes.
    private func pull(_ width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in drag = -sign * value.translation.width }
            .onEnded { value in finish(value, width) }
    }

    /// The whole-screen drag, watched for on the rail and on the drawer. A real minimum distance,
    /// or a tap becomes a one-pixel drag and the screen twitches under every touch.
    private func swipe(_ width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onChanged { value in
                guard mine(value) else { return }
                drag = -sign * value.translation.width
            }
            // Whatever this turned into by the time the finger left, a drag this one has already
            // moved the drawer for is this one's to put down. Asking `mine` again here is how the
            // drawer ends up parked halfway: swipe in, change your mind, come back, let go.
            .onEnded { value in
                guard drag != 0 else { return }
                finish(value, width)
            }
    }

    /// Whether this drag is the one that moves the drawer: sideways rather than up the page, and
    /// pointing the way there is something to move. Closed, only on the rail; open, anywhere on it
    /// while the tray shows. On the manager's half that drag is the halves' (`ManagerView.halves`):
    /// it turns back to the tray, and only from there does the same drag put the drawer away.
    private func mine(_ value: DragGesture.Value) -> Bool {
        guard abs(value.translation.width) > abs(value.translation.height) else { return false }
        let inward = -sign * value.translation.width > 0
        return desk.open ? !inward && desk.tab == .tray : inward && !desk.covered
    }

    /// In or out, decided on where it was let go *and* where it was going: a flick that covered a
    /// third of the drawer means the same as a slow drag across most of it.
    private func finish(_ value: DragGesture.Value, _ width: CGFloat) {
        let moved = -sign * value.translation.width
        let thrown = -sign * value.predictedEndTranslation.width
        let far = abs(moved) > width / 3 || abs(thrown) > width / 2
        settle(open: far ? moved > 0 : desk.open)
    }

    private func settle(open: Bool) {
        withAnimation(Motion.opening) {
            if open && !desk.open {
                desk.pullIn(waiting: waiting)
            } else {
                desk.open = open
            }
            drag = 0
        }
    }
}
