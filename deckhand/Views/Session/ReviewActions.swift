import DeckhandKit
import SwiftUI

/// The foot of the review card: where the words are going, and the things you can do about them.
///
/// It was one line of 11pt words eight points apart, Discard close enough to Edit to be taken for
/// it. A control here is at the app's reading size with 44pt of finger under it, and it is a
/// capsule — see `face` for why that stopped being a clash.
///
/// Three things, not four, and not three of a kind. Edit and Send are the two you press, so they
/// are the two filled ones and they stand together at the end you press things at. Discard is the
/// one that loses something: it keeps its 44pt of finger and gives up its fill, so it is quiet
/// and it is as far from Send as the row is wide — distance is the actual fix for hitting the
/// wrong one, not a confirmation. Adding to the words moved out from between them altogether and
/// went under the prompt, where the words it records land; see `SayRest`.
struct ReviewActions: View {
    let route: String
    /// The words as they stand, which is what Send sends and what a second clip lands beneath.
    let words: String
    let discard: () -> Void
    let edit: () -> Void
    let send: (String) -> Void
    /// A deck column, which is 240pt wide and has room for none of this.
    var compact = false
    @Environment(\.accent) private var accent

    /// The minimum a finger can be asked to hit. The same raw number `FilesView` writes, and for
    /// the same reason: no spacing token means "a finger", and rounding it to one that exists
    /// would be picking a number off a list instead of off a hand.
    private static let touch: CGFloat = 44

    var body: some View {
        if compact { tight } else { roomy }
    }

    /// The session page and the overview: room for real controls, so they are real controls.
    ///
    /// The session's name stood over this row until it did not. A full card only ever opens on that
    /// session's own page, whose header names it — so the line said again what the screen already
    /// said, and it was the one item here nobody taps. A deck column keeps it: there the columns
    /// stand side by side and the name is what tells one card from the next.
    private var roomy: some View {
        HStack(spacing: Spacing.xxs) {
            Button(action: discard) { quiet("Discard", glyph: "trash") }
                .buttonStyle(.plain)
            // Collapses to nothing but its minimum on a narrow phone, so Send takes whatever
            // width is left over rather than a fixed half of the row.
            Spacer(minLength: Spacing.extraSmall)
            Button { send(words) } label: {
                face("Send", glyph: "paperplane.fill", ink: .white, fill: accent, weight: .semibold)
            }
            .buttonStyle(.plain)
        }
    }

    /// A deck column. Unchanged: 44pt controls would be taller than the card they sit in.
    private var tight: some View {
        HStack(spacing: Spacing.small) {
            Text("→ \(route)")
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
            Spacer(minLength: Spacing.extraSmall)
            Button("Discard", action: discard)
                .buttonStyle(.plain)
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
            Button("Edit", action: edit)
                .buttonStyle(.plain)
                .font(Typography.hint)
                .foregroundStyle(accent)
            Button("Send") { send(words) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(accent)
        }
    }

    /// The one that loses something, in the quiet colour with no fill under it. Still 44pt of
    /// finger and still the full width of the word, because a control that is easy to miss on
    /// purpose is a different thing from one that is hard to hit at all.
    ///
    /// The bin is the one glyph here that has to be read *before* the word rather than with it:
    /// this is the control somebody hits by accident, and a shape carries further than four
    /// letters in the quiet colour do.
    private func quiet(_ label: String, glyph: String) -> some View {
        Label(label, systemImage: glyph)
            .font(.system(size: 14))
            .foregroundStyle(Palette.textTertiary)
            .lineLimit(1)
            .padding(.horizontal, Spacing.extraSmall)
            .frame(minHeight: Self.touch)
            .contentShape(.capsule)
    }

    /// One button. Equal width to its sibling, 44pt tall, and the label centred in it.
    ///
    /// A capsule, and the corner audit is what changed rather than the arithmetic. The audit was
    /// right: a 44pt capsule is a 22pt corner, and sitting 16pt inside a card whose own corner is
    /// 12 the inner curve is *wider* than the one it is nested in, which reads as fighting. The
    /// answer it reached — tighten the button to `Radius.small` — fixed the arithmetic and left a
    /// row of small hard rectangles at the foot of a soft card, which is what JJ was looking at
    /// when he said he hated it.
    ///
    /// So the nesting went instead of the radius. This row is drawn *outside* the card now (see
    /// `ReviewCard.body`), on the page's own ground, nested in nothing — and a control nested in
    /// nothing is free to be the shape iOS makes a 44pt control. Nothing is concentric with
    /// anything here, so nothing can clash with it.
    private func face(
        _ label: String,
        glyph: String,
        ink: Color,
        fill: Color,
        weight: Font.Weight = .regular
    ) -> some View {
        Label(label, systemImage: glyph)
            .font(.system(size: 14, weight: weight))
            .foregroundStyle(ink)
            .lineLimit(1)
            // Only the narrowest phones with the longest word, and shrinking a point beats
            // truncating "Discard" to "Disca…".
            .minimumScaleFactor(0.85)
            .padding(.horizontal, Spacing.extraSmall)
            .frame(maxWidth: .infinity, minHeight: Self.touch)
            .background(Capsule().fill(fill))
            .contentShape(.capsule)
    }
}
