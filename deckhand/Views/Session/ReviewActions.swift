import DeckhandKit
import SwiftUI

/// The foot of the review card: where the words are going, and the things you can do about them.
///
/// It was one line of 11pt words eight points apart, Discard close enough to Edit to be taken for
/// it. The rule here is the one `FilesView`'s selector already set: a control is a capsule at the
/// app's reading size with 44pt of finger under it.
///
/// Three things, not four, and not three of a kind. Edit and Send are the two you press, so they
/// are the two capsules and they stand together at the end you press things at. Discard is the
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
    private var roomy: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            // Its own line now. Sharing one with the buttons, it was the thing being squeezed
            // when a name got long — and it is the one item here nobody taps.
            Text("→ \(route)")
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
            HStack(spacing: Spacing.xxs) {
                Button(action: discard) { quiet("Discard") }
                    .buttonStyle(.plain)
                // Collapses to nothing but its minimum on a narrow phone, which is what keeps
                // the two capsules the same width as each other at every size.
                Spacer(minLength: Spacing.extraSmall)
                Button(action: edit) {
                    face("Edit", ink: accent, fill: Palette.tileIdle)
                }
                .buttonStyle(.plain)
                Button { send(words) } label: {
                    face("Send", ink: .white, fill: accent, weight: .semibold)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A deck column. Unchanged: 44pt capsules would be taller than the card they sit in.
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
    private func quiet(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 14))
            .foregroundStyle(Palette.textTertiary)
            .lineLimit(1)
            .padding(.horizontal, Spacing.extraSmall)
            .frame(minHeight: Self.touch)
            .contentShape(.rect)
    }

    /// One capsule. Equal width to its sibling, 44pt tall, and the label centred in it.
    private func face(
        _ label: String,
        ink: Color,
        fill: Color,
        weight: Font.Weight = .regular
    ) -> some View {
        Text(label)
            .font(.system(size: 14, weight: weight))
            .foregroundStyle(ink)
            .lineLimit(1)
            // Only the narrowest phones with the longest word, and shrinking a point beats
            // truncating "Discard" to "Disca…".
            .minimumScaleFactor(0.85)
            .padding(.horizontal, Spacing.extraSmall)
            .frame(maxWidth: .infinity, minHeight: Self.touch)
            .background(Capsule().fill(fill))
            .contentShape(.rect)
    }
}
