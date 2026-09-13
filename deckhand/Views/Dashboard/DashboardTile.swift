import DeckhandKit
import SwiftUI

/// One square on a session's dashboard: what it is, what is true of it right now, and the thing
/// tapping it opens.
///
/// **A tile is never only a button.** The rule the whole grid is built on is that a square earns
/// its place by carrying a fact somebody would otherwise have to open something to learn — how
/// many slips are waiting, how full the window is, what the standing orders actually say. A tile
/// holding nothing but a word in a box is a menu row drawn four times too large, and the menu it
/// replaced was better at being that. Where there was no true number to put on one, the item
/// stayed in the menu instead.
///
/// It is a `Card`, not a shape of its own, so a grid of these is the same surface every other
/// page in this app is built from. Nothing is nested inside it: the value and the caption are
/// text on the card's own ground, never a second rounded rectangle, which is the muddy look
/// utt's notes name by name and the reason `Radius` has no step below `small`.
struct DashboardTile: View {
    /// The symbol, top left. Small on purpose: it is a signpost for an eye moving across a grid
    /// rather than decoration, and the line under it is the thing being read.
    let glyph: String
    /// What this square is, in the eyebrow voice this app uses everywhere for "what am I looking
    /// at" — 9pt mono, uppercase, tracked.
    let title: String
    /// What is true of it now. The one line that has to survive being read at arm's length.
    let value: String
    /// The quieter second fact, where there is one worth the room.
    var caption: String?
    /// The colour the value is drawn in when it is asking for something — a slip waiting, an
    /// inbox nobody has read, a window nearly full. Nil is the ordinary state and reads as ink.
    var lit: Color?
    /// Whether there is anything behind it. Every tile that is a keystroke in a pane is *dimmed*
    /// rather than removed when iTerm cannot be reached: that the thing exists is worth keeping
    /// on the grid, and the caption says why it cannot be pressed.
    var ready = true
    /// What VoiceOver hears, where the eyebrow is shorter than the action it names. The two
    /// control tiles are the whole reason this exists — "STOP" is enough to read and not enough
    /// to hear.
    var spoken: String?
    let act: () -> Void

    var body: some View {
        Button(action: act) {
            Card(spacing: Spacing.extraSmall) {
                head
                Spacer(minLength: 0)
                Text(value)
                    .font(Typography.pageTitle)
                    .foregroundStyle(lit ?? Palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                if let caption {
                    Text(caption)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .opacity(ready ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(said)
        .accessibilityIdentifier(identifier)
    }

    /// The glyph and the eyebrow on one line, which is the only row of the square that is
    /// furniture. Everything below it is the fact.
    private var head: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: glyph)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(lit ?? Palette.textTertiary)
            Text(title.uppercased())
                .font(Typography.state)
                .tracking(0.8)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    /// One sentence for a screen reader: what it is, what it says, and the caveat underneath.
    /// Built here rather than left to SwiftUI's own combining, which reads the eyebrow's
    /// uppercase as initials.
    private var said: String {
        [spoken ?? title, value, caption].compactMap { $0 }.joined(separator: ", ")
    }

    /// Stable enough for a UI test to name one square without the grid having to hand out ids.
    private var identifier: String {
        "tile-" + title.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}
