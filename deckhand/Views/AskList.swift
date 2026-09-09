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
/// The three states differ by **how much of the square is filled**, never by a second shape put
/// inside the first. It used to be a rounded outline holding a smaller rounded rectangle, which
/// at the 9pt size a row uses meant two corner radii under two points each and a 1.2pt border
/// landing between pixels — a mark that read as a smudge rather than a box.
///
/// So: no radius at all, a 1pt border on the pixel grid, and integral geometry. Empty is not
/// started, the left half filled is under way, solid is done.
struct AskDot: View {
    let state: Ask.State
    var size: CGFloat = 11
    @Environment(\.accent) private var accent

    var body: some View {
        ZStack(alignment: .leading) {
            if state == .done {
                // The fill *is* the square when it is done. Nothing is drawn on top of it, so
                // there is no border sitting a fraction of a point outside a filled shape.
                Rectangle().fill(edge)
            } else {
                Rectangle().strokeBorder(edge, lineWidth: 1)
                // Half, rounded to a whole point so the edge of the fill lands where the pixels
                // are. Under way is genuinely half a box rather than a smaller box.
                if state == .doing {
                    Rectangle().fill(edge).frame(width: (size / 2).rounded())
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var edge: Color {
        switch state {
        case .done: accent
        case .doing: Palette.lcdYellow
        case .todo: Palette.textTertiary
        }
    }
}

/// The same list at a glance: one dot per ask, for a row that has no space for words. Says
/// how much is left without saying what any of it is.
struct AskDots: View {
    let asks: [Ask]

    /// A row is narrower than a page, so it shows fewer. Same reasoning as `AskList.shown`.
    private static let shown = 12

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(asks.suffix(Self.shown)) { ask in AskDot(state: ask.progress, size: 9) }
        }
        .accessibilityElement()
        .accessibilityLabel("\(asks.filter { $0.progress == .done }.count) of \(asks.count) done")
    }
}
