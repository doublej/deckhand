import DeckhandKit
import SwiftUI

/// What you have asked a session for, and how far each one got.
///
/// It is your list, not the session's plan: it is written from your own messages, one line per
/// ask, and the only judgement in it is whether the session has started on that ask, is in the
/// middle of it, or has finished it.
struct AskList: View {
    let asks: [Ask]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("WHAT YOU ASKED FOR")
                .font(Typography.eyebrow)
                .tracking(1)
                .foregroundStyle(Palette.textTertiary)
            VStack(alignment: .leading, spacing: Spacing.small) {
                ForEach(asks) { ask in
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

/// One ask as a dot, in the language the rest of the app already speaks: filled is finished,
/// the recording colour is under way, an outline is not started.
struct AskDot: View {
    let state: Ask.State
    var size: CGFloat = 9

    var body: some View {
        Group {
            switch state {
            case .done: Circle().fill(Palette.tint)
            case .doing: Circle().fill(Palette.lcdYellow)
            case .todo: Circle().strokeBorder(Palette.textTertiary, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The same list at a glance: one dot per ask, for a row that has no space for words. Says
/// how much is left without saying what any of it is.
struct AskDots: View {
    let asks: [Ask]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(asks) { ask in AskDot(state: ask.progress, size: 6) }
        }
        .accessibilityElement()
        .accessibilityLabel("\(asks.filter { $0.progress == .done }.count) of \(asks.count) done")
    }
}
