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
    /// Favourites are no longer a section of their own — a star would split a project in two —
    /// so the mark that used to be the section header is now on the row itself.
    let starred: Bool
    /// Where this row sits in its project's block. Only the ends of a block are rounded: four
    /// rows that each round their own four corners read as four cards that happen to touch,
    /// which is exactly what grouping them was meant to stop.
    let first: Bool
    let last: Bool
    /// The rail's accent, which is utt orange while any row on it is listening.
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            GlyphTile(DotGlyph.forName(session.name), size: 32, prominent: current || talk.isRecording)
                // Where a thread to this session starts and ends. On the tile rather than the
                // row, so the light comes out of the session's own face and no arithmetic
                // about padding is needed anywhere.
                .anchorPreference(key: SessionNodes.self, value: .bounds) {
                    [session.sessionId: $0]
                }
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
                    progress.padding(.top, Spacing.xxs)
                }
                // How full its context is, as the shape alone: the number belongs on the
                // session's own page, and what a row needs to say is "this one is nearly
                // out of room" without spending a line on it.
                if let context = session.context {
                    Meter(context.share, tint: Palette.pressure(context.pressure), thickness: 2)
                        .padding(.top, Spacing.extraSmall)
                }
            }
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(slab.fill(Color.primary.opacity(current ? 0.11 : 0.045)))
        // The one row that is listening says so in the language the rest of the app uses for
        // it: utt's orange, around the row rather than through it, so the words stay readable
        // while you are speaking about them.
        .overlay {
            if talk.isRecording || talk.busy {
                slab.strokeBorder(Palette.recording, lineWidth: 1.5)
            }
        }
        .contentShape(.rect)
        // How long it has been quiet, said as presence rather than as another line of text.
        // Applied last so it carries the tile and the border with the words — fading only the
        // ink would leave a bright empty tile behind a dim name, which reads as a loading row.
        // Hit testing is unaffected by opacity, so a faded row is still as tappable as any.
        //
        // A row with a slip waiting on you keeps full contrast whatever the clock says, for the
        // same reason a busy one does: the fade spends contrast on how long ago something
        // happened, and a question nobody has answered has not happened yet. A session that
        // stopped to ask you something this morning is the row you most need to see at six.
        .opacity(talk.isRecording || talk.busy || current || session.waitingPages > 0
                 ? 1 : session.contrast())
    }

    /// The ground this row sits on, and the border it takes while it is listening — one shape,
    /// so the two can never round differently. Square where the block continues.
    private var slab: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: first ? Radius.medium : 0,
            bottomLeadingRadius: last ? Radius.medium : 0,
            bottomTrailingRadius: last ? Radius.medium : 0,
            topTrailingRadius: first ? Radius.medium : 0,
            style: .continuous
        )
    }

    /// How far the two things you are in the middle of with this session have got: what you asked
    /// it for, as one dot each, and the slips it asked you for, as the two numbers.
    ///
    /// One band, because they are the same question — what is still open between the two of you —
    /// and a row has one place to answer it.
    private var progress: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            if !asks.isEmpty {
                band("checklist", in: Palette.textTertiary) { AskDots(asks: asks) }
            }
            if session.pages > 0 {
                band("doc.richtext", in: session.waitingPages > 0 ? accent : Palette.textTertiary) {
                    Text(slipsLine)
                        .font(Typography.hint)
                        .accessibilityLabel(slipsLine)
                }
            }
        }
    }

    /// One line of the pair, and the reason they read as a pair at all.
    ///
    /// A fixed gutter rather than a glyph tucked in front of the words: at 12pt every line's
    /// content starts on the same vertical, so the dots and the sentence below them line up like
    /// two entries in a list instead of two unrelated things that happen to be stacked. The line
    /// keeps a minimum height so a row with one band and a row with two have the same rhythm
    /// rather than the same total.
    ///
    /// The glyph takes its line's colour rather than a fixed grey. A slip waiting turns the whole
    /// line accent, gutter included; anything quiet stays quiet all the way across. Half-tinting
    /// a line is what made these two clash when they shared one.
    private func band(
        _ symbol: String,
        in colour: Color,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(spacing: Spacing.extraSmall) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 12, alignment: .leading)
            content()
        }
        .foregroundStyle(colour)
        .frame(minHeight: 18)
    }

    /// Both numbers, because "one waiting" and "one of six waiting" are different situations and
    /// the row is the only place that can say which this is. Words where the asks are dots, and
    /// deliberately not a second run of the same mark: `AskDot` is a box you tick, its own note
    /// warns against a second thing reading as that mark, and two runs of identical marks in one
    /// row cannot be told apart without a label costing more than the words do.
    private var slipsLine: String {
        let noun = session.pages == 1 ? "slip" : "slips"
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
            if starred {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(accent)
                    .accessibilityLabel("Starred")
            }
            StateWord(talk.isRecording ? .rec : talk.busy ? .wait : session.isBusy ? .busy : .idle)
        }
    }
}
