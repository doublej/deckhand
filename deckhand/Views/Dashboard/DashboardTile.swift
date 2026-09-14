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
    /// What the number is *of* — which slips, which subagents, which files — at most three lines
    /// of it. This is the preview area, and it is the difference between a square somebody reads
    /// and a caption floating in a box: the tile that already had one was the only tile on the
    /// first grid that looked finished. Empty where there is nothing true to put here, and then
    /// the tile is simply shorter rather than padded out to a shape.
    var preview: [String] = []
    /// What kind of thing those lines are, so the square says it before a word of it is read —
    /// a slip draws as a page, a subagent as something typed at a prompt, a file in mono. The
    /// default is plain sentences, which is what a square whose preview is prose still wants.
    var look: TileLook = .lines
    /// The same fact as a bar, where the fact is a share of something. Only the window has one:
    /// "372k of 450k" is arithmetic somebody has to do, and the bar is the answer already done.
    var meter: Double?
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

    /// The eyebrow, the number, what the number is of, and the caveat last.
    ///
    /// **The height is the content's and nothing else's.** Every tile was a literal square, with
    /// the eyebrow pinned to the top and the number to the bottom and a third of the card empty
    /// between them — which on screen reads as a card that failed to load, and cost so much room
    /// that two and a half rows of a twelve-square grid were visible at once. The number moved up
    /// under the eyebrow, the preview took the middle, and a row is now as tall as the tallest
    /// thing in it. Squares with nothing to preview are honestly short, and since the grid is
    /// already ordered "things you look at" before "things you do", the tall rows come first.
    ///
    /// **A tile with nothing to preview is short, not stretched.** Filling the row's height was
    /// tried first and it put the void straight back: ORDERS with nothing standing, drawn to the
    /// height of a FILES square listing three filenames, is the same empty card as before under
    /// another rule. The cards hug their content and the grid top-aligns them, so what is left
    /// over falls *between* squares, where it reads as a gutter, rather than inside one, where it
    /// reads as a square that failed to load.
    var body: some View {
        Button(action: act) {
            Card(spacing: Spacing.extraSmall) {
                head
                Text(value)
                    .font(Typography.pageTitle)
                    .foregroundStyle(lit ?? Palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                if let meter { Meter(meter, tint: lit ?? Palette.tint) }
                lines
                if let caption {
                    Text(caption)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                        .padding(.top, Spacing.xxs)
                }
            }
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

    /// The preview lines, each drawn as its kind — see `TileLook`. Secondary ink rather than
    /// tertiary: this is the content of the square, not a footnote to it, and the caption
    /// underneath is the thing that should recede. Indexed rather than keyed on the line itself,
    /// because two files in two folders share a name.
    private var lines: some View {
        ForEach(Array(preview.enumerated()), id: \.offset) { _, line in
            TileLine(look: look, words: line)
        }
    }

    /// One sentence for a screen reader: what it is, what it says, and the caveat underneath.
    /// Built here rather than left to SwiftUI's own combining, which reads the eyebrow's
    /// uppercase as initials.
    private var said: String {
        // The preview is read out too. It is the content of the square rather than decoration,
        // and a tile that says "Agents, 16 finished" to a screen reader while saying which
        // sixteen to everybody else has quietly made the grid worth less to one of them.
        ([spoken ?? title, value] + preview + [caption].compactMap { $0 })
            .joined(separator: ", ")
    }

    /// Stable enough for a UI test to name one square without the grid having to hand out ids.
    private var identifier: String {
        "tile-" + title.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}
