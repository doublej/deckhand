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
                if let agent = agents[tool.toolId] {
                    Button { open(agent) } label: { AgentFace(agent: agent) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("agent-row")
                } else {
                    // No transcript to open yet. It still says what was asked for, because the
                    // tool call carries that much, and a row that vanishes and reappears is
                    // worse than a quiet one.
                    AgentFace(title: tool.detail.isEmpty ? "agent" : tool.detail,
                              line: tool.name, running: !tool.succeeded, openable: false)
                }
            }
        }
        .padding(.horizontal, Spacing.extraSmall)
        .padding(.vertical, Spacing.xxs)
    }
}

/// The agents still going that nothing on this page of the conversation started.
///
/// A transcript is a page — the last handful of turns — so an agent spawned two hundred turns ago
/// is running with the row that would open it nowhere on screen. Those are exactly the ones worth
/// reaching, which is why they are gathered here instead of being left to a scroll back through a
/// conversation to a call that stopped being interesting hours ago.
///
/// **Running only, and that is what keeps it from being clutter.** Every agent a session has ever
/// started, listed for ever at the foot of its transcript, would be a second listing nobody asked
/// for; this is empty the moment the work is done, which is the same rule `ActiveLine` — the line
/// it sits directly above — already follows.
struct LooseAgents: View {
    let agents: [Agent]
    let open: (Agent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            // Named, because a stack of rows floating above the working line with no word on it
            // is the same puzzle this view exists to fix.
            Text("STILL GOING")
                .font(Typography.eyebrow)
                .tracking(1)
                .foregroundStyle(Palette.textTertiary)
            ForEach(agents) { agent in
                Button { open(agent) } label: { AgentFace(agent: agent) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("agent-row")
            }
        }
        .padding(.horizontal, Spacing.extraSmall)
        .padding(.vertical, Spacing.xxs)
    }
}

/// One agent as a row, openable or not.
///
/// **It looks pressable on purpose**, the way `WaitingSlip` does and for the same reason: the
/// tell used to be a 10pt tertiary chevron on a fill the un-openable row wore too, so a row you
/// could open and a row you could not were the same row. The two things that say otherwise are
/// borrowed rather than invented — a finger's 44 points of height, spelled as `FilesView` spells
/// it, and the app's own tint on the chevron, which is the colour of every other thing here that
/// answers a tap. The fill stays `tileIdle`: how a subagent reads inside the transcript was the
/// half that was already right.
private struct AgentFace: View {
    let title: String
    let line: String
    let running: Bool
    let openable: Bool

    /// The minimum a finger can be asked to hit, as `FilesView` spells it: no spacing token means
    /// "a finger", and rounding it to the nearest step either lies or overshoots.
    private static let target: CGFloat = 44

    init(title: String, line: String, running: Bool, openable: Bool) {
        self.title = title
        self.line = line
        self.running = running
        self.openable = openable
    }

    init(agent: Agent) {
        self.init(title: agent.title, line: agent.line, running: agent.running, openable: true)
    }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.extraSmall) {
            mark
            words
            Spacer(minLength: 0)
            if openable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.tint)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .padding(.horizontal, Spacing.extraSmall)
        .frame(maxWidth: .infinity, minHeight: Self.target, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(Palette.tileIdle)
        )
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(openable ? .isButton : [])
        .accessibilityLabel(spoken)
    }

    private var words: some View {
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
    @ViewBuilder private var mark: some View {
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

    /// What it is and what it is doing, said once — without this VoiceOver reads the title, the
    /// quiet line and the chevron as three separate things and the state as nothing at all.
    private var spoken: String {
        let state = running ? "still going" : "finished"
        let said = line.isEmpty ? title : "\(title), \(line)"
        return openable ? "\(said), \(state). Opens its conversation" : "\(said), \(state)"
    }
}
