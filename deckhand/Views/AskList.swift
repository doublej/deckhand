import DeckhandKit
import SwiftUI

/// What you have asked a session for, and how far each one got.
///
/// It is your list, not the session's plan: it is written from your own messages, one line per
/// ask, and the only judgement in it is whether the session has started on that ask, is in the
/// middle of it, or has finished it.
struct AskList: View {
    let asks: [Ask]

    /// How many of them a page shows. The Mac keeps the whole history — the agent is not allowed
    /// to trim it, because a list that trims itself is a list that forgets — so the cut is made
    /// here, where it is a question about a screen rather than about the record.
    private static let shown = 8

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("WHAT YOU ASKED FOR")
                .font(Typography.eyebrow)
                .tracking(1)
                .foregroundStyle(Palette.textTertiary)
            if asks.count > Self.shown {
                Text("\(asks.count - Self.shown) older, on the Mac")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: Spacing.small) {
                ForEach(asks.suffix(Self.shown)) { ask in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                        AskDot(state: ask.progress)
                        Text(ask.text)
                            .font(Typography.prose)
                            .foregroundStyle(ask.progress == .done
                                             ? Palette.textTertiary
                                             : Palette.textPrimary)
                            .strikethrough(ask.progress == .done, color: Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One ask as a box you can tick. Square on purpose: a round dot is what a tool call wears in
/// the transcript, and two different things reading as the same mark is worse than either.
///
/// Empty is not started, a small mark inside is under way, a filled one is done.
struct AskDot: View {
    let state: Ask.State
    var size: CGFloat = 11

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .strokeBorder(edge, lineWidth: 1.2)
            .frame(width: size, height: size)
            .overlay {
                if state != .todo {
                    RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                        .fill(edge)
                        .frame(width: size * inside, height: size * inside)
                }
            }
            .accessibilityHidden(true)
    }

    private var edge: Color {
        switch state {
        case .done: Palette.tint
        case .doing: Palette.lcdYellow
        case .todo: Palette.textTertiary
        }
    }

    /// Done fills the box; under way is a smaller mark in it, so the two differ by more than
    /// colour alone.
    private var inside: CGFloat {
        state == .done ? 0.52 : 0.34
    }
}

/// The same list at a glance: one dot per ask, for a row that has no space for words. Says
/// how much is left without saying what any of it is.
struct AskDots: View {
    let asks: [Ask]

    /// A row is narrower than a page, so it shows fewer. Same reasoning as `AskList.shown`.
    private static let shown = 12

    var body: some View {
        HStack(spacing: 4) {
            ForEach(asks.suffix(Self.shown)) { ask in AskDot(state: ask.progress, size: 9) }
        }
        .accessibilityElement()
        .accessibilityLabel("\(asks.filter { $0.progress == .done }.count) of \(asks.count) done")
    }
}
