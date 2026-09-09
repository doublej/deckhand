import DeckhandKit
import SwiftUI

/// One round of conversation. Yours are marked down the edge in the app's own colour, so a
/// glance down the transcript tells you who said what without reading a word of it.
struct TurnCard: View {
    let turn: Turn
    /// False when the turn before this one was from the same speaker.
    let showsRole: Bool
    /// Set on your last message while nothing has answered it: BUSY if the session is working
    /// on it, WAIT if it has not picked it up yet.
    var waiting: PillState?

    var body: some View {
        Card(spacing: Spacing.xxs) {
            if showsRole || waiting != nil {
                HStack(spacing: Spacing.extraSmall) {
                    Text(turn.isUser ? "YOU" : "CLAUDE")
                        .font(Typography.eyebrow)
                        .tracking(1)
                        .foregroundStyle(turn.isUser ? Palette.tint : Palette.textTertiary)
                    Spacer(minLength: 0)
                    if let waiting {
                        Text(waiting == .busy ? "working on it" : "not picked up yet")
                            .font(Typography.hint)
                            .foregroundStyle(Palette.textTertiary)
                        StatePill(waiting)
                    }
                }
            }
            Text(turn.text)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
        }
        .overlay(alignment: .leading) {
            if turn.isUser {
                // A rail rather than a different ground: the transcript stays one column of
                // cards, and yours are the ones with a line down the side.
                Capsule()
                    .fill(Palette.tint)
                    .frame(width: 3)
                    .padding(.vertical, Spacing.extraSmall)
            }
        }
    }
}

/// Something you said that is sitting in the session's inbox, not picked up yet.
///
/// It looks like your turn because it is one — it simply is not in the transcript, and cannot
/// be, until the session absorbs it. Speaking into a session that is mid-turn is the normal
/// way to use this app; the only confusing part was having no way to tell that from having
/// sent nothing at all.
struct QueuedCard: View {
    let item: Queued
    /// Stops the run so the session reads this next. Absent when there is no run to stop, or
    /// when the session already took it.
    let force: (() -> Void)?

    var body: some View {
        Card(spacing: Spacing.xxs) {
            HStack(spacing: Spacing.extraSmall) {
                Text("YOU")
                    .font(Typography.eyebrow)
                    .tracking(1)
                    .foregroundStyle(Palette.tint)
                Spacer(minLength: 0)
                Text(item.line)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                StatePill(item.isWaiting ? .wait : .busy)
            }
            Text(item.text)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
            if let force {
                // The honest label. There is no way to make a session read its inbox early —
                // the inbox is drained when the turn ends — so this ends the turn, and says so.
                Button("Stop the run so it reads this", systemImage: "forward.end", action: force)
                    .buttonStyle(.plain)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.tint)
                    .padding(.top, Spacing.xxs)
            }
        }
        .overlay(alignment: .leading) {
            // Dashed, where a turn's rail is solid: the same voice, not yet in the record.
            Capsule()
                .strokeBorder(Palette.tint, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: 3)
                .padding(.vertical, Spacing.extraSmall)
        }
    }
}
