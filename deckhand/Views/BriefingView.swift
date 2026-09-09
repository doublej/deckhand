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
                prose
                // Under the briefing, not above it: the first line of a briefing is what to do
                // right now, and a checklist in front of that buries it.
                if let asks = model.tasks[session.sessionId], !asks.isEmpty {
                    Divider()
                    AskList(asks: asks)
                }
                // The one thing in this app that costs money, said out loud rather than left
                // to be discovered on a bill.
                if let spent = model.spend[session.sessionId], spent.runs > 0 {
                    Text(spent.line)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textTertiary)
                }
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
