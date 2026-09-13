import DeckhandKit
import SwiftUI

/// Every subagent this session has, in one place, opened from the dashboard's square.
///
/// **The transcript already lists some of them and that is exactly the problem this answers.**
/// `AgentTrace` draws the agents one *turn* started, and `LooseAgents` gathers the running ones
/// whose spawning call has scrolled off the page — both are readings of the conversation, so
/// finding an agent meant knowing roughly when it was started and scrolling to it. The square
/// says how many are working without opening anything, and this is what it opens onto.
///
/// Two headings rather than one, which is the one place it parts company with `LooseAgents`.
/// That view is running-only on purpose: a permanent listing of everything ever started, pinned
/// to the foot of a transcript, is a second transcript nobody asked for. A square is the opposite
/// case — it is the place a full listing *was* asked for — and a session that has just finished
/// six agents has six conversations worth reading. So running first, then the rest, and the
/// eyebrow says which is which.
///
/// The rows are `AgentFace`, the same row the transcript draws, and the destination is
/// `AgentView`, the same one. Nothing here is a second reading of anything.
struct AgentList: View {
    @Bindable var model: AppModel
    let session: Session
    /// The subagent whose own conversation is open. Its sheet is declared here rather than on the
    /// dashboard, so it presents *over* the sheet this list is on — a view presents one at a time.
    @State private var reading: Agent?

    /// Newest first, because the model holds these in a dictionary and a dictionary has no order:
    /// without this the rows would shuffle on every poll, exactly as `Agent.loose` reasons.
    private var agents: [Agent] {
        model.agents.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.medium) {
                if agents.isEmpty { nothing }
                section("Still going", agents.filter(\.running))
                section("Finished", agents.filter { !$0.running })
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.medium)
            .padding(.top, Spacing.small)
            .padding(.bottom, Spacing.extraLarge)
        }
        .frame(maxHeight: .infinity)
        .fadingEdges()
        .sheet(item: $reading) { AgentView(model: model, session: session, agent: $0) }
    }

    /// One heading and its rows, or nothing at all when that half is empty — a heading over no
    /// rows says a thing exists that does not.
    @ViewBuilder private func section(_ title: String, _ found: [Agent]) -> some View {
        if !found.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title.uppercased())
                    .font(Typography.eyebrow)
                    .tracking(1)
                    .foregroundStyle(Palette.textTertiary)
                ForEach(found) { agent in
                    Button { reading = agent } label: { AgentFace(agent: agent) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("agent-row")
                }
            }
        }
    }

    /// A Mac a version behind and a session that has started nothing are the same answer here —
    /// none — which is what `AppModel.loadAgents` already decided, so this says one thing.
    private var nothing: some View {
        Text("This session has not started any subagents")
            .font(Typography.subtitle)
            .foregroundStyle(Palette.textTertiary)
            .padding(.top, Spacing.large)
    }
}
