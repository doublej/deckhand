import DeckhandKit
import SwiftUI

/// The two answers an overview can give about words it is holding: send them as they stand, or go
/// where they can be worked on properly.
///
/// **Neither overview has a staging area, and neither is getting one.** The rail had the deck
/// column's card — 10pt words, the verbs crushed onto one line — on a full-width phone, and the
/// fix is not a second copy of the card the session's own page already gets right. It is these
/// two, which are the answers a person actually has while looking at a wall of sessions.
///
/// **Refine carries nothing, and that is the whole trick.** Words held for reading already live
/// on the model under the session's own id — `review`, with `reviewFiltered`, `reviewTiming`,
/// `heldClips` and `attached` beside it — and `SessionFoot` draws its card straight out of them.
/// So carrying the clip across *is* opening the session: the card is there when the page arrives,
/// with the chain's notes, the round-trip line and anything pinned to it. Nothing is handed over,
/// so there is nothing that can fall out of step.
///
/// **A refusal is the one thing this has to say out loud.** The card's red line is where that
/// normally lives and there is no card here, so a filter that will not pass these words would be
/// a Send button that quietly does nothing — and `delivered: true` has never meant it was said.
///
/// Throwing the words away is not offered. It is the one answer that loses something, and it
/// belongs beside the words it is losing, which is one tap away behind Refine.
struct SendOrRefine: View {
    /// The words being held, which is what Send sends. Never edited here — editing them is the
    /// whole of what Refine is for.
    let words: String
    /// Whose words they are: the hint that says where Refine goes, and in a deck column the word
    /// that tells one card from the next.
    let target: String
    /// What the chain will do to them if they go as they stand, where it will do anything at all.
    let refusal: String?
    let send: (String) -> Void
    let refine: () -> Void
    /// A deck column, which is 240 points wide and has room for none of the row below.
    var compact = false
    @Environment(\.accent) private var accent

    /// The minimum a finger can be asked to hit. The same raw number `ReviewActions`, `SayRest`
    /// and `FilesView` write, and for the same reason: no spacing token means "a finger".
    private static let touch: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            if let refusal {
                // The colour is the whole of the difference, as everywhere else in this app: the
                // words alone in the state's own colour, never a label inside a capsule that
                // reads as something you press — and there is a real button just below it.
                Text(refusal)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.lcdRed)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if compact { tight } else { verbs }
        }
        // The row's own inner gutter, so these line up with the session's glyph above them rather
        // than with the edge its slab bleeds out to. A column sets its own, outside.
        .padding(.horizontal, compact ? 0 : Spacing.small)
        .padding(.bottom, compact ? 0 : Spacing.extraSmall)
    }

    /// A deck column. `ReviewActions.tight`'s row minus the verb this surface does not offer:
    /// 44pt controls would be taller than the column they sit in, so these are words at the
    /// deck's own size. The session's name stays, because the columns stand side by side and it
    /// is what tells one card from the next — on the rail the row above already said it.
    private var tight: some View {
        HStack(spacing: Spacing.small) {
            Text("→ \(target)")
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
            Spacer(minLength: Spacing.extraSmall)
            Button("Refine", action: refine)
                .buttonStyle(.plain)
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHint("Opens \(target) with these words ready to change")
                .accessibilityIdentifier("refine-prompt")
            Button("Send") { send(words) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(accent)
                .accessibilityIdentifier("send-prompt")
        }
    }

    /// `ReviewActions.roomy`'s arrangement, because the thumb that learned it there is the same
    /// thumb: the one that finishes the prompt is filled and at the end you press things at, the
    /// other is quiet and as far from it as the row is wide. Distance is the actual fix for
    /// hitting the wrong one.
    private var verbs: some View {
        HStack(spacing: Spacing.xxs) {
            Button(action: refine) { quiet("Refine", glyph: "square.and.pencil") }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(target) with these words ready to change")
                .accessibilityIdentifier("refine-prompt")
            Spacer(minLength: Spacing.extraSmall)
            Button { send(words) } label: { face("Send", glyph: "paperplane.fill") }
                .buttonStyle(.plain)
                .accessibilityIdentifier("send-prompt")
        }
    }

    /// The way back into the words, in the quiet colour with no fill under it. Edit's own glyph,
    /// because the card it opens is where this lands and Edit is what is waiting there.
    private func quiet(_ label: String, glyph: String) -> some View {
        Label(label, systemImage: glyph)
            .font(.system(size: 14))
            .foregroundStyle(Palette.textTertiary)
            .lineLimit(1)
            .padding(.trailing, Spacing.extraSmall)
            .frame(minHeight: Self.touch)
            .contentShape(.capsule)
    }

    /// A capsule, nested in nothing: this row stands on the rail's own ground rather than inside
    /// a card, which is exactly the condition under which a 44pt control may be the shape iOS
    /// makes one. See `ReviewActions.face`, where the same argument is written out in full.
    private func face(_ label: String, glyph: String) -> some View {
        Label(label, systemImage: glyph)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, Spacing.extraSmall)
            .frame(maxWidth: .infinity, minHeight: Self.touch)
            .background(Capsule().fill(accent))
            .contentShape(.capsule)
    }
}
