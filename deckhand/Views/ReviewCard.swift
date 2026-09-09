import DeckhandKit
import SwiftUI

/// What was heard, held until you say so. Borrowed from utt's own review HUD: the transcript,
/// where it is going, and the two things you can do about it. utt offers ⏎ and ⎋ because a
/// panel that never takes focus makes the keys the real interface; a phone has no keys, so
/// the buttons are the whole affordance.
struct ReviewCard: View {
    let text: String
    let target: String
    let send: () -> Void
    let discard: () -> Void
    /// Small enough for a deck column, which has no room for a full card.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            Text(text)
                .font(compact ? .system(size: 10) : Typography.mono)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(compact ? 4 : 6)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.extraSmall) {
                Text("→ \(target)")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.extraSmall)
                Button("Discard", action: discard)
                    .buttonStyle(.plain)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textSecondary)
                Button("Send", action: send)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Palette.tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? Spacing.extraSmall : Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(Palette.tint.opacity(0.4), lineWidth: 1)
        )
    }
}
