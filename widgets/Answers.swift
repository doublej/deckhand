import DeckhandKit
import SwiftUI

/// A confirm slip this card can answer: which one, and the words on its two buttons.
struct Answerable {
    let slip: String
    let accept: String
    let decline: String
    /// Set when the slip is a decision, which the card's Yes then signs for.
    let hash: String?
}

extension Deck.ContentState {
    /// The slip this card can answer, when the Mac sent all three of its parts.
    var answerable: Answerable? {
        guard let slip, let accept, let decline else { return nil }
        return Answerable(slip: slip, accept: accept, decline: decline, hash: hash)
    }
}

/// No and Yes for the slip whose question is the card's line, below the sentence rather than
/// beside the name: the card's job is to be read, and a control beside the identity would be the
/// first thing the eye lands on. Yes is the filled one and sits last, where a thumb ends up.
///
/// Not mono and not tracked, which is deliberate. `WAIT` above is the state vocabulary, and the
/// design layer's rule is that a state is never a thing you press. `Radius.small` and not a
/// capsule, for the same reason a filled control inside a card is: corners get tighter inwards.
/// Ink on the teal is `lcdGround`, 5:1, where white would be 2.6:1.
struct Answers: View {
    let deck: Deck
    let ask: Answerable

    var body: some View {
        HStack(spacing: Spacing.extraSmall) {
            choice(ask.decline, yes: false, fill: Palette.tileIdle, ink: Palette.textPrimary)
            choice(ask.accept, yes: true, fill: Palette.tint, ink: Palette.lcdGround)
        }
        // Buttons first when the row is short of width; the age beside them is the spacer.
        .layoutPriority(1)
    }

    private func choice(_ label: String, yes: Bool, fill: Color, ink: Color) -> some View {
        Button(intent: AnswerSlip(session: deck.session, slip: ask.slip, hash: ask.hash, yes: yes)) {
            Text(label)
                .font(Typography.primaryRow)
                .foregroundStyle(ink)
                .lineLimit(1)
                .padding(.horizontal, Spacing.small)
                .padding(.vertical, Spacing.extraSmall)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(fill)
                )
                // The pill draws at ~31pt; Apple's floor for anything you tap is 44. The extra
                // points are hit area and nothing else, which is why `contentShape` makes them count.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
