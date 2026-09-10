import DeckhandKit
import SwiftUI

/// The one thin line on the rail, and the only chrome on it: the mark, whatever is wrong, the
/// daemon's state, and the two places you can go. It was two lines, one at each end, and the
/// top one spent a band of the screen saying what this one already says.
///
/// Its own file rather than a computed property on `SessionListView`, which is at the 300-line
/// cap: the rail's foot is the one part of that page nothing else on it depends on.
struct RailFoot: View {
    @Bindable var model: AppModel
    @Binding var showSettings: Bool
    @Binding var showProjects: Bool

    var body: some View {
        HStack(spacing: Spacing.small) {
            Wordmark()
            if let reason {
                Text(reason)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.extraSmall)
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
        // Even, so the mark sits in the middle of the band rather than at the foot of it. The
        // home indicator is the safe area's job now, not this padding's.
        .padding(.vertical, Spacing.small)
    }

    /// What the pill cannot carry: the reason. Nothing at all when the Mac is simply there.
    private var reason: String? {
        switch model.connection {
        case .connected(let iterm): iterm == "ok" ? nil : iterm
        default: model.status ?? model.connection.label
        }
    }
}
