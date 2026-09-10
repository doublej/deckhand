import DeckhandKit
import SwiftUI

/// The foot of the rail, and the only chrome on it: whatever is wrong, the daemon's state, the
/// two places you can go — and under all of it, centred, the app's own name.
///
/// Its own file rather than a computed property on `SessionListView`, which is at the 300-line
/// cap: the rail's foot is the one part of that page nothing else on it depends on.
///
/// **What is not here.** JJ asked for the `+` to become a prominent iTerm control at the top of
/// the screen. That is deliberately not done: this page had a top line once and it was taken
/// away on purpose — it "spent a band of the screen saying what this one already says" — so
/// putting one back is a decision for JJ rather than for a port to make on his behalf.
struct RailFoot: View {
    @Bindable var model: AppModel
    @Binding var showSettings: Bool
    @Binding var showProjects: Bool

    /// Two centred rows: what the rail can tell you and what you can do with it, and under
    /// them the app's own name.
    var body: some View {
        VStack(spacing: Spacing.xxs) {
            controls
            // Centred and alone the mark is a statement rather than a signature, so it is
            // quieter than it was at the end of the line: 11pt and held back. The proportions
            // inside it — grey word, accent period — are utt's and are untouched.
            Wordmark(size: 11)
                .opacity(0.5)
                // Down into the margin rather than down the layout, so the controls above do
                // not rise to pay for it — the same move `SessionFoot` makes for the talk mark,
                // and for the same reason: their height is a decision that was already made.
                //
                // The arithmetic. The ink on this page stops at the safe area, 34pt above the
                // glass on this phone; 16 of those points put the mark 18pt up, which is clear
                // of the home indicator's own pill. It is a signature and not a control, so it
                // is the one thing here that may sit in that margin at all — nothing is aimed
                // at it, so nothing is lost to the system's swipe-up zone below it.
                .offset(y: Spacing.medium)
        }
        .frame(maxWidth: .infinity)
        // The room the mark takes comes out of the bottom margin rather than pushing the
        // controls up the screen. The home indicator is still the safe area's job.
        .padding(.top, Spacing.small)
    }

    /// What remains of the line once the mark has left it, as a cluster in the middle rather
    /// than a row pinned to the two edges. Nothing here moved up or down: the height is the one
    /// it had, and the mark's row was taken out of the margin below it.
    private var controls: some View {
        HStack(spacing: Spacing.small) {
            if let reason {
                Text(reason)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            // Only when there is nothing wrong. One line holds one of the two: what the Mac is
            // spending while it is fine, or what is broken about it — and the reason is a
            // sentence, so it is the thing that would be squeezed to an ellipsis by these.
            if reason == nil { Statusline(model: model) }
            StateWord(model.connection.state)
            Button("New session", systemImage: "plus") { showProjects = true }
                .accessibilityIdentifier("new-session")
            Button("Hidden sessions", systemImage: model.showsHidden ? "eye" : "eye.slash") {
                model.showsHidden.toggle()
            }
            Button("Settings", systemImage: "gearshape") { showSettings = true }
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Palette.textTertiary)
        .padding(.horizontal, Spacing.small)
    }

    /// What the pill cannot carry: the reason. Nothing at all when the Mac is simply there.
    private var reason: String? {
        switch model.connection {
        case .connected(let iterm): iterm == "ok" ? nil : iterm
        default: model.status ?? model.connection.label
        }
    }
}
