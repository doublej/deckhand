import DeckhandKit
import SwiftUI

/// One subagent's own conversation, opened from the turn that started it.
///
/// The same three pieces the session's own transcript is drawn with — `ToolTrace`, `TurnCard`,
/// and nothing else — because the rows are literally the same rows: Claude Code writes a
/// subagent's transcript in the same shape as a session's, and the Mac reads it with the same
/// parser. A second reading here would be a second set of bugs.
///
/// **No talking.** There is no field at the bottom and no route behind one. A subagent has no
/// inbox socket and no name anything could address — it is a conversation the session is having,
/// not a session — so reading is the whole of the surface, and it is refused by absence.
struct AgentView: View {
    @Bindable var model: AppModel
    let session: Session
    let agent: Agent
    @Environment(\.dismiss) private var dismiss
    @State private var turns: [Turn] = []
    @State private var loading = true
    @State private var earlier = false
    @State private var stepping = false

    var body: some View {
        NavigationStack {
            Group {
                if loading && turns.isEmpty {
                    ProgressView().tint(Palette.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if turns.isEmpty {
                    nothing
                } else {
                    reading
                }
            }
            .background(Palette.surfaceGround)
            .navigationTitle(agent.kind.isEmpty ? "Agent" : agent.kind)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(Palette.tint)
                }
            }
        }
        .task { await load() }
    }

    private var reading: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.extraSmall) {
                head
                if earlier { step }
                ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        if !turn.tools.isEmpty { ToolTrace(tools: turn.tools) }
                        if !turn.text.isEmpty || !turn.thoughts.isEmpty {
                            TurnCard(turn: turn, showsRole: startsRun(index), theirWord: "AGENT")
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.bottom, Spacing.medium)
        }
    }

    /// What it was asked for, at the top, because the prompt is the parent's and everything below
    /// it is the agent's answer to it — and on a phone the two are easy to confuse.
    private var head: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(agent.title)
                .font(Typography.primaryRow)
                .foregroundStyle(Palette.textPrimary)
            Text(agent.running ? "\(agent.line) · still going" : agent.line)
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.small)
    }

    private var step: some View {
        Button {
            guard !stepping else { return }
            stepping = true
            Task { await older() }
        } label: {
            Text(stepping ? "Reading…" : "Earlier")
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.extraSmall)
        }
        .buttonStyle(.plain)
    }

    private var nothing: some View {
        Text(agent.running ? "It has not said anything yet." : "Nothing was written down.")
            .font(Typography.primaryRow)
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The same rule the session's transcript uses: a name over a turn only when the speaker
    /// changed, so a run of one side's messages reads as one voice.
    private func startsRun(_ index: Int) -> Bool {
        index == 0 || turns[index - 1].role != turns[index].role
    }

    private func load() async {
        guard let client = model.settings.client() else { return }
        let rounds = try? await client.turns(ofAgent: agent.id, in: session.sessionId, limit: 12)
        turns = rounds?.turns ?? []
        earlier = rounds?.more ?? false
        loading = false
    }

    private func older() async {
        defer { stepping = false }
        guard let client = model.settings.client() else { return }
        let held = turns.count
        guard let rounds = try? await client.turns(ofAgent: agent.id, in: session.sessionId,
                                                   limit: 12, before: held) else { return }
        turns = rounds.turns + turns
        earlier = rounds.more
    }
}
