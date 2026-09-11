import DeckhandKit
import SwiftUI

/// One round of conversation. Yours are marked down the edge in the app's own colour, so a
/// glance down the transcript tells you who said what without reading a word of it.
struct TurnCard: View {
    let turn: Turn
    /// False when the turn before this one was from the same speaker.
    let showsRole: Bool
    /// What the other speaker is called. A session's transcript is Claude; the manager panel is
    /// the manager, and calling it Claude there would be the one screen where the word said
    /// nothing — every session on that panel is Claude too.
    var theirWord = "CLAUDE"
    /// What a hold on the words opens, where this screen has somewhere for it to go.
    ///
    /// It goes on the words and never on the card, which is the trap this repo has already paid
    /// for three times: a long press applied *outside* a control takes the touch from it, and
    /// the card holds the thinking toggle. Nil leaves the turn exactly as it was — whole-card
    /// selection, which is the only thing `.textSelection` does on iOS — and that is the manager
    /// panel, which has no reader of its own.
    var onHold: (() -> Void)?
    @Environment(\.accent) private var accent
    /// Closed until asked. Thinking is the longest thing in a turn and the least often wanted —
    /// a transcript that opened every block by default would be a transcript nobody could skim.
    @State private var thinking = false

    var body: some View {
        Card(spacing: Spacing.xxs) {
            header
            // Above the words, which is where it happened: this is how it got to what it says
            // next, the same argument that puts the tool trace above a message rather than under.
            thought
            said
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

    /// Who said it, and when.
    ///
    /// One row rather than two, because the speaker is only drawn at the top of a run and the
    /// time is drawn on every turn: on the second turn of a run this row is the time alone,
    /// hanging off the right edge where the eye already knows to find it. Skipped entirely when
    /// there is neither — the manager panel builds its turns with no stamp, and an empty row
    /// there would be a gap that means nothing.
    @ViewBuilder private var header: some View {
        if showsRole || !turn.clock.isEmpty {
            HStack(spacing: Spacing.extraSmall) {
                if showsRole {
                    Text(turn.speaker(theirs: theirWord))
                        .font(Typography.eyebrow)
                        .tracking(1)
                        .foregroundStyle(turn.isUser ? accent : Palette.textTertiary)
                }
                Spacer(minLength: 0)
                Text(turn.clock)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .monospacedDigit()
                    .accessibilityIdentifier("turn-time")
            }
        }
    }

    /// What it thought on the way here, behind one line you can press.
    ///
    /// A turn still in flight has thinking and no words yet, so this is also how a session reads
    /// while it is working — nothing special is done for the live case, it simply arrives with
    /// the page like everything else and the poll keeps it current.
    @ViewBuilder private var thought: some View {
        if !turn.thoughts.isEmpty {
            Button { withAnimation(Motion.opening) { thinking.toggle() } } label: {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(thinking ? 90 : 0))
                    Text(count)
                        .font(Typography.eyebrow)
                        .tracking(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.textTertiary)
                .frame(minHeight: 26)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("thinking-toggle")
            if thinking {
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    ForEach(Array(turn.thoughts.enumerated()), id: \.offset) { _, said in
                        Text(said)
                            .font(.system(size: 12))
                            .italic()
                            .foregroundStyle(Palette.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                // A rail down the side, in the quiet colour: the same shape that marks your own
                // turns, so a block of italics inside a card still reads as set apart from it.
                .padding(.leading, Spacing.extraSmall)
                .overlay(alignment: .leading) {
                    Capsule().fill(Palette.textTertiary.opacity(0.3)).frame(width: 2)
                }
                .padding(.bottom, Spacing.xxs)
                .transition(.opacity)
            }
        }
    }

    /// Said as a count rather than "Thinking", because the number is the part that tells you
    /// whether opening it is worth the scroll.
    private var count: String {
        turn.thoughts.count == 1 ? "THOUGHT" : "\(turn.thoughts.count) THOUGHTS"
    }

    /// What was said, drawn as the document it is.
    ///
    /// The document renderer rather than ``Prose``, and the reason is what each contract is for.
    /// `Prose` draws the four things a *summary* may contain and shows anything else as the
    /// characters the model typed, because a summary is written against a prompt this repo owns
    /// and a briefing that broke that contract must look broken. A turn has no contract to break:
    /// it is whatever a person dictated or another session wrote, and what another session writes
    /// is markdown — headings, `code`, **bold**, bullets, numbered steps, fences, tables. Every
    /// one of those used to land here as punctuation, which is the same failure `Prose` exists to
    /// expose, arriving for the opposite reason. ``Markdown`` is also where the fence rule already
    /// lives, and a third renderer would be a third place that rule could drift out of step.
    ///
    /// A hold on it opens ``TurnReader`` where the screen has one, and then the turn carries no
    /// `.textSelection` at all — two meanings for one press is how a gesture goes silently dead,
    /// and the reader gives back everything the modifier did (Select All, then Copy) plus the
    /// range selection it never could.
    @ViewBuilder private var said: some View {
        if !turn.text.isEmpty {
            if let onHold {
                Markdown(turn.text)
                    // The air between blocks is part of the turn, so a hold that lands in it has
                    // to count; without a shape only the ink itself is pressable.
                    .contentShape(.rect)
                    .onLongPressGesture(perform: onHold)
                    // On a container, and knowingly: this renames every `Text` under it, which
                    // is the trap the manager panel fell into — but a rendered block has no
                    // identifier of its own to lose, and the press has to land on one of them.
                    .accessibilityIdentifier("turn-words")
            } else {
                Markdown(turn.text)
                    .textSelection(.enabled)
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
