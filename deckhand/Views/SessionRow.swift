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
                if !asks.isEmpty {
                    AskDots(asks: asks).padding(.top, 2)
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
        .opacity(talk.isRecording || talk.busy || current ? 1 : session.contrast())
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
