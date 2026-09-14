import DeckhandKit
import SwiftUI

/// What kind of thing a square's preview lines are, so a glance says it before a word is read.
///
/// Every tile drew its three lines in one voice — 11pt text, the same for a slip, a subagent and
/// a filename — so the *kind* of thing in a square could only be learned by reading it. These are
/// the kinds, and each draws its lines as the thing behind them: a slip is an HTML page and gets
/// a page, a subagent is a machine working and gets the prompt it would be typed at, a file gets
/// the type a file is read in.
///
/// **It changes the line, never the ground.** Nothing here draws a second filled rectangle inside
/// the card — that is the nesting utt's notes name by name and the rule `DashboardTile` is built
/// on, which is why a terminal line is mono type behind a chevron rather than a dark slab of its
/// own. The one drawn shape is `PageMark`, and it is a glyph at glyph scale, the same standing as
/// the symbol already on the tile's eyebrow.
enum TileLook {
    /// Sentences somebody wrote or named: the standing orders, the filters running.
    case lines
    /// Slips. Each line is an HTML page a session wrote, so each line carries one.
    case pages
    /// Something a machine is doing, behind the prompt it would be typed at: the subagents, and
    /// the prompts queued in an inbox waiting to be typed into a session.
    case terminal
    /// A file on disk: the files it touched, the CLAUDE.md files it started with.
    case files
}

/// One preview line, drawn as its kind: a mark saying what it is, and the line itself.
struct TileLine: View {
    let look: TileLook
    let words: String

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            mark
            Text(words)
                // The same 11pt regular either way — in SF Mono where the line is something a
                // machine wrote or a file is called, which is a rendering of `Typography.hint`
                // rather than a second size nobody picked.
                .font(look == .lines ? Typography.hint : Typography.hint.monospaced())
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
        }
    }

    /// What sits in front of the words. Tertiary ink for all of them: the mark says what kind of
    /// thing this is, and the tile's own `lit` is what says whether it wants something.
    @ViewBuilder private var mark: some View {
        switch look {
        case .lines:
            EmptyView()
        case .pages:
            PageMark()
        case .terminal:
            // The prompt, in the 9pt mono the app already uses for a machine's voice.
            Image(systemName: "chevron.right")
                .font(Typography.state)
                .foregroundStyle(Palette.textTertiary)
        case .files:
            Image(systemName: "doc")
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
        }
    }
}

/// A slip, at the size of the line it sits on: the page it actually is.
///
/// Square corners, because a page is a sheet of paper and `Radius` has no step small enough to
/// round one this size into anything but a lozenge. Ruled rather than a symbol: what a session
/// writes is an HTML page with a heading and some text under it, and at this scale that shape
/// says *page* where `doc.richtext` says "a document icon" — which is the decoration this whole
/// change exists to avoid. No fill either, so it is a drawing on the card's own ground rather
/// than a surface nested in it, and it is right on both the light ground and the dark one.
private struct PageMark: View {
    private let width: CGFloat = 10
    private let height: CGFloat = 13
    /// What is left for the rules once the border and its margin are taken off.
    private var inside: CGFloat { width - 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 1.5) {
            // The heading, and it runs the full width on purpose: at 0.8 it was a third dash and
            // the mark read as three grey lines in a box. A solid band across the top is what
            // makes the rest of it read as the text under a heading.
            rule(1, thickness: 3)
            rule(1, thickness: 1)
            rule(0.6, thickness: 1)
            Spacer(minLength: 0)
        }
        .padding(2)
        .frame(width: width, height: height)
        .overlay(Rectangle().strokeBorder(Palette.textTertiary.opacity(0.55), lineWidth: 0.75))
        .accessibilityHidden(true)
    }

    /// One ruled line inside the page. The thick one is its heading and is drawn darker, which
    /// is the whole difference between this and three grey dashes.
    private func rule(_ share: CGFloat, thickness: CGFloat) -> some View {
        Rectangle()
            .fill(Palette.textTertiary.opacity(thickness > 1 ? 0.85 : 0.45))
            .frame(width: inside * share, height: thickness)
    }
}
