import DeckhandKit
import SwiftUI

/// One line of the manager's conversation.
///
/// Two shapes and the reason for both. What was *said* is a bubble, the person's on the trailing
/// side and the manager's on the leading one, the way every chat on this phone reads: the panel is
/// a conversation with one other party, and who said what is the first thing a glance needs. A
/// session's transcript keeps its column of `TurnCard`s — that is a record to read down, this is
/// a thread to reply in. What was *done* is not a bubble at all. It is a line under the words, the way a tool trace sits under a message, because a card
/// promises something to read and "said to deckhand: run the tests" is something to glance at.
struct ManagerLine: View {
    let entry: ManagerEntry
    @Environment(\.accent) private var accent

    var body: some View {
        switch entry.role {
        case .person:
            ManagerBubble(text: entry.text, mine: true)
        case .manager:
            ManagerBubble(text: entry.text, mine: false)
        case .act:
            note(entry.text, word: "DID", tint: Palette.textTertiary)
        case .command:
            note(entry.text, word: "PHONE", tint: accent)
        case .note:
            note(entry.text, word: "MAC", tint: Palette.lcdYellow)
        }
    }

    /// A thing that happened, in one line: the word, then what it was. No ground behind it and
    /// no box around it — the cards are the conversation and these are the margin of it.
    private func note(_ text: String, word: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.extraSmall) {
            Text(word)
                .font(Typography.eyebrow)
                .tracking(1)
                .foregroundStyle(tint)
            Text(text)
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.extraSmall)
        .accessibilityElement()
        .accessibilityLabel("\(word): \(text)")
    }
}

/// Something said, on its own side of the panel.
///
/// One paragraph hugs its words, the way a chat bubble does; anything longer is the manager's
/// list of sessions or a fenced block, which needs the full document renderer and so the width
/// it fills. Either way the far side keeps a margin, so the two speakers never share a column.
struct ManagerBubble: View {
    let text: String
    let mine: Bool
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 0) {
            if mine { Spacer(minLength: Spacing.extraLarge + Spacing.medium) }
            words
                .padding(.horizontal, Spacing.small)
                .padding(.vertical, Spacing.extraSmall)
                .background(
                    RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        .fill(mine ? accent.opacity(0.22) : Palette.surfacePrimary)
                )
            if !mine { Spacer(minLength: Spacing.extraLarge + Spacing.medium) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mine ? "You" : "Manager"): \(text)")
    }

    @ViewBuilder private var words: some View {
        if !text.contains("\n"), let inline = try? AttributedString(markdown: text) {
            // The 6 `Markdown` sets a paragraph at, so a one-paragraph reply and a longer one
            // read at the same line height side by side.
            Links.text(inline)
                .font(Typography.prose)
                .foregroundStyle(Palette.textPrimary)
                .lineSpacing(6)
                .textSelection(.enabled)
        } else {
            Markdown(text).textSelection(.enabled)
        }
    }
}
