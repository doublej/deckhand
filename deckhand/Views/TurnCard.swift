import DeckhandKit
import SwiftUI

/// One round of conversation. Yours are marked down the edge in the app's own colour, so a
/// glance down the transcript tells you who said what without reading a word of it.
struct TurnCard: View {
    let turn: Turn
    /// False when the turn before this one was from the same speaker.
    let showsRole: Bool
    @Environment(\.accent) private var accent

    var body: some View {
        Card(spacing: Spacing.xxs) {
            if showsRole {
                Text(turn.isUser ? "YOU" : "CLAUDE")
                    .font(Typography.eyebrow)
                    .tracking(1)
                    .foregroundStyle(turn.isUser ? accent : Palette.textTertiary)
            }
            Text(Links.marked(turn.text, in: accent))
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
        }
        .overlay(alignment: .leading) {
            if turn.isUser {
                // A rail rather than a different ground: the transcript stays one column of
                // cards, and yours are the ones with a line down the side.
                Capsule()
                    .fill(accent)
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
    let text: String
    /// Stops the run so the session reads this next. Absent when there is no run to stop.
    let force: (() -> Void)?
    @Environment(\.accent) private var accent

    var body: some View {
        Card(spacing: Spacing.xxs) {
            HStack(spacing: Spacing.extraSmall) {
                Text("YOU")
                    .font(Typography.eyebrow)
                    .tracking(1)
                    .foregroundStyle(accent)
                Spacer(minLength: 0)
                Text("waiting in its inbox")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                StateWord(.wait)
            }
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
            if let force {
                // The honest label. There is no way to make a session read its inbox early —
                // the inbox is drained when the turn ends — so this ends the turn, and says so.
                Button("Stop the run so it reads this", systemImage: "stop.circle.fill", action: force)
                    .buttonStyle(.plain)
                    .font(Typography.hint)
                    .foregroundStyle(accent)
                    .padding(.top, Spacing.xxs)
            }
        }
        .overlay(alignment: .leading) {
            // Dashed, where a turn's rail is solid: the same voice, not yet in the record.
            Capsule()
                .strokeBorder(accent, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: 3)
                .padding(.vertical, Spacing.extraSmall)
        }
    }
}

/// Where the session is right now, at the live end of the transcript.
///
/// A transcript is a record of what has happened, and with a busy session the most useful line
/// in it is the one that has not finished happening. This used to be a pill on your last
/// message, which made it disappear the moment the session answered you and went off to run
/// things — precisely when you most want to know it is still going, and on what.
///
/// No card: it sits in the gap after the last card, so the place the conversation has reached
/// is the one thing on the screen that is not a card.
struct ActiveLine: View {
    /// The newest thing it ran, when it has run anything since it last spoke.
    let doing: Tool?
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: Spacing.extraSmall) {
            // The one moving thing in the transcript, because the one thing it says is
            // "still going". A phase animator rather than state and an `onAppear`: this sits
            // in a lazy stack, and a pulse that has to be restarted by hand comes back dead.
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
                .phaseAnimator([0.2, 1.0]) { dot, lit in dot.opacity(lit) }
            Text("WORKING")
                .font(Typography.eyebrow)
                .tracking(1)
                .foregroundStyle(accent)
            Text(what)
                .font(Typography.mono)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.extraSmall)
        .padding(.vertical, Spacing.extraSmall)
        .background(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(accent.opacity(0.07))
        )
        .accessibilityElement()
        .accessibilityLabel("Working: \(what)")
        .accessibilityIdentifier("active-line")
    }

    /// What it is on. A tool is the honest answer whenever there is one; the rest of the time it
    /// is working out what to say, and there is no better word for that than thinking.
    private var what: String {
        guard let doing else { return "thinking" }
        return doing.detail.isEmpty ? doing.name : "\(doing.name) \(doing.detail)"
    }
}
