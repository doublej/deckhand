import DeckhandKit
import SwiftUI

/// The subagents one turn started, as rows of their own rather than dots in the tool trace.
///
/// **This is the whole point of the split.** A subagent was drawn as a tool call because it
/// arrives as one — a `tool_use` block like any other — but it is a conversation: it has its own
/// transcript, its own steps, and it is still going long after the dot that started it stopped
/// being interesting. A dot cannot say "running", cannot say how far along, and cannot be opened.
///
/// A row with no `Agent` behind it still draws, from the tool call alone, and simply does not
/// open. That happens for two honest reasons: a Mac a version behind serves no `/agents` at all,
/// and an agent started a second ago has a `tool_use` block before it has a meta file.
struct AgentTrace: View {
    /// This turn's `Agent`/`Task` calls, in the order they were made.
    let tools: [Tool]
    /// Every subagent the session has, by the tool call that started it.
    let agents: [String: Agent]
    let open: (Agent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            ForEach(tools) { tool in
                row(tool, agents[tool.toolId])
            }
        }
        .padding(.horizontal, Spacing.extraSmall)
        .padding(.vertical, Spacing.xxs)
    }

    @ViewBuilder private func row(_ tool: Tool, _ agent: Agent?) -> some View {
        if let agent {
            Button { open(agent) } label: { face(agent.title, agent.line, agent.running, true) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("agent-row")
        } else {
            // No transcript to open yet. It still says what was asked for, because the tool call
            // carries that much, and a row that vanishes and reappears is worse than a quiet one.
            face(tool.detail.isEmpty ? "agent" : tool.detail, tool.name, !tool.succeeded, false)
        }
    }

    private func face(_ title: String, _ line: String, _ running: Bool, _ openable: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.extraSmall) {
            mark(running).padding(.top, 3)
            words(title, line)
            Spacer(minLength: 0)
            if openable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, Spacing.extraSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(Palette.tileIdle)
        )
        .contentShape(.rect)
    }

    private func words(_ title: String, _ line: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(Typography.cardLabel)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if !line.isEmpty {
                Text(line)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    /// Running is a ring, finished is a filled dot. A ring rather than a spinner: a turn can hold
    /// six of these and six spinners is a screen that will not sit still.
    @ViewBuilder private func mark(_ running: Bool) -> some View {
        if running {
            Circle()
                .strokeBorder(Palette.lcdYellow, lineWidth: 1.5)
                .frame(width: 7, height: 7)
        } else {
            Circle()
                .fill(Palette.textTertiary)
                .frame(width: 7, height: 7)
        }
    }
}
