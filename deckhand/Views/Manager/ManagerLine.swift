import DeckhandKit
import SwiftUI

/// One line of the manager's conversation.
///
/// Two shapes and the reason for both. What was *said* — by the person or by the manager — is a
/// `TurnCard`, the same card the session transcript draws, because it is the same thing: a round
/// of a conversation, in markdown, from one of two speakers. What was *done* is not a card at
/// all. It is a line under the words, the way a tool trace sits under a message, because a card
/// promises something to read and "said to deckhand: run the tests" is something to glance at.
struct ManagerLine: View {
    let entry: ManagerEntry
    /// False when the line before this one was the same kind. Only the cards use it; a run of
    /// four acts reads as four acts without a heading on each.
    let showsRole: Bool
    @Environment(\.accent) private var accent

    var body: some View {
        switch entry.role {
        case .person:
            TurnCard(turn: Turn(role: "user", text: entry.text, timestamp: ""),
                     showsRole: showsRole)
        case .manager:
            TurnCard(turn: Turn(role: "assistant", text: entry.text, timestamp: ""),
                     showsRole: showsRole)
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
