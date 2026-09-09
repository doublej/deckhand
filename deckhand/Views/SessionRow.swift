import DeckhandKit
import SwiftUI

/// One session as a rail row: its glyph, its name, what it needs from you, and how far it has
/// got through what you asked.
///
/// The headline is the row. It is written to about twelve words, but a model writing prose is
/// not a layout engine — so the row gives it three lines and real leading rather than clipping
/// the one sentence the page exists to show.
struct SessionRow: View {
    let session: Session
    let current: Bool
    /// What this session needs from you, in one line. Absent until the Mac has read it.
    let headline: String?
    /// What you have asked it for, as one dot each. Empty until the Mac has read it.
    let asks: [Ask]
    /// Whether this is the row the microphone is open for, and whether the clip is on its way.
    let talk: TalkState
    /// The rail's accent, which is utt orange while any row on it is listening.
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            GlyphTile(DotGlyph.forName(session.name), size: 32, prominent: current || talk.isRecording)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                title
                // The row is worth its extra height only when there is something in it; a
                // placeholder saying "reading…" on six rows at once is worse than nothing.
                if let headline {
                    Text(headline)
                        .font(Typography.subtitle)
                        .foregroundStyle(Palette.textSecondary)
                        .lineSpacing(3)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !asks.isEmpty || session.pages > 0 {
                    progress.padding(.top, 2)
                }
                // How full its context is, as the shape alone: the number belongs on the
                // session's own page, and what a row needs to say is "this one is nearly
                // out of room" without spending a line on it.
                if let context = session.context {
                    Meter(context.share, tint: Palette.pressure(context.pressure), thickness: 2)
                        .padding(.top, Spacing.xxs)
                }
            }
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Color.primary.opacity(current ? 0.11 : 0.045))
        )
        // The one row that is listening says so in the language the rest of the app uses for
        // it: utt's orange, around the row rather than through it, so the words stay readable
        // while you are speaking about them.
        .overlay {
            if talk.isRecording || talk.busy {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(Palette.recording, lineWidth: 1.5)
            }
        }
        .contentShape(.rect)
        // How long it has been quiet, said as presence rather than as another line of text.
        // Applied last so it carries the tile and the border with the words — fading only the
        // ink would leave a bright empty tile behind a dim name, which reads as a loading row.
        // Hit testing is unaffected by opacity, so a faded row is still as tappable as any.
        //
        // A row with a page waiting on you keeps full contrast whatever the clock says, for the
        // same reason a busy one does: the fade spends contrast on how long ago something
        // happened, and a question nobody has answered has not happened yet. A session that
        // stopped to ask you something this morning is the row you most need to see at six.
        .opacity(talk.isRecording || talk.busy || current || session.waitingPages > 0
                 ? 1 : session.contrast())
    }

    /// How far the two things you are in the middle of with this session have got: what you asked
    /// it for, as one dot each, and the pages it asked you for, as the two numbers.
    ///
    /// One band, because they are the same question — what is still open between the two of you —
    /// and a row has one place to answer it.
    private var progress: some View {
        HStack(spacing: Spacing.extraSmall) {
            if !asks.isEmpty { AskDots(asks: asks) }
            if session.pages > 0 { pages }
        }
    }

    /// The pages as words where the asks are dots, and deliberately not a second run of dots.
    ///
    /// `AskDot` is a box you can tick and that is the one thing it means here; a second row of the
    /// same mark standing for something else is what its own note warns against, and two runs of
    /// identical marks in one band cannot be told apart without a label that costs more than the
    /// words do. Both numbers, because "one waiting" and "one of six waiting" are different
    /// situations and the row is the only place that can say which this is.
    ///
    /// The accent does the rest: nothing else in a row's words is ever this colour, so a page
    /// waiting is the one thing on the rail that reads as addressed to you — and it says so
    /// without a second state word beside the one the title already carries. Everything answered
    /// goes quiet instead, which is the whole point of saying both.
    private var pages: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 10, weight: .semibold))
            Text(pagesLine)
        }
        .font(Typography.hint)
        .foregroundStyle(session.waitingPages > 0 ? accent : Palette.textTertiary)
        .accessibilityElement()
        .accessibilityLabel(pagesLine)
    }

    private var pagesLine: String {
        let noun = session.pages == 1 ? "page" : "pages"
        return session.waitingPages > 0
            ? "\(session.waitingPages) of \(session.pages) \(noun) waiting"
            : "\(session.pages) \(noun) answered"
    }

    /// The name and the state on one baseline, so the headline below them has the full width.
    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.extraSmall) {
            Text(session.name)
                .font(Typography.primaryRow)
                .fontWeight(current ? .semibold : .medium)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Spacing.extraSmall)
            StateWord(talk.isRecording ? .rec : talk.busy ? .wait : session.isBusy ? .busy : .idle)
        }
    }
}
