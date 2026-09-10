import DeckhandKit
import SwiftUI

/// What the session did while you were away, with the whole page to say it in: the briefing
/// itself, then what you asked it for, then what writing it cost.
struct BriefingView: View {
    @Bindable var model: AppModel
    let session: Session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.extraLarge) {
                // Above the briefing, unlike the checklist below it: a slip with no answer
                // beside it is the session stopped and waiting on a person, which is what to do
                // right now. The prose is what it did before it stopped.
                if let asking = waiting.first {
                    WaitingSlip(model: model,
                                session: session,
                                artifact: asking,
                                more: waiting.count - 1)
                }
                prose
                // Under the briefing, not above it: the first line of a briefing is what to do
                // right now, and a checklist in front of that buries it.
                //
                // No rule between them any more. The gap and the eyebrow already say a section
                // has started — a divider on top of both was a third separator doing the same
                // job, and three of them read as clutter rather than as structure.
                if let asks = model.tasks[session.sessionId], !asks.isEmpty {
                    AskList(asks: asks)
                }
                spend
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.medium)
            // The opening sentence needs room above it or it reads as a caption stuck to the
            // header rather than the first thing on a page.
            .padding(.top, Spacing.large)
            .padding(.bottom, Spacing.extraLarge)
        }
        .frame(maxHeight: .infinity)
        // Room at the end for the bar that floats over this.
        .contentMargins(.bottom, TalkMark.clearance, for: .scrollContent)
        // The listing and not `session.waitingPages`, which is a number: a link has to know
        // which slip it opens and what that slip is called. A directory listing on the Mac,
        // asked for when the tab is opened, exactly as the Slips tab asks for it.
        .task { await model.loadArtifacts(for: session) }
    }

    /// The one thing in this app that costs money, said out loud rather than left to be
    /// discovered on a bill. A foot rather than a fourth section: a rule above it and pinned to
    /// the end of the page, so it is the last thing read and never mistaken for a heading.
    @ViewBuilder private var spend: some View {
        if let spent = model.spend[session.sessionId], spent.runs > 0 {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Rectangle()
                    .fill(Palette.textTertiary.opacity(0.2))
                    .frame(height: 1)
                Text(spent.line)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    /// The slips this session is waiting on an answer for, newest first as the Mac sorted them.
    private var waiting: [Artifact] {
        (model.artifacts[session.sessionId] ?? []).filter { !$0.answered }
    }

    @ViewBuilder private var prose: some View {
        if let text = model.summaries[session.sessionId] {
            Prose(text)
        } else {
            Text(model.waiting.contains(session.sessionId)
                 || model.summarising.contains(session.sessionId)
                 ? "Reading what it did…"
                 : "Nothing yet")
                .font(Typography.subtitle)
                .foregroundStyle(Palette.textSecondary)
        }
    }
}
