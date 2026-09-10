import DeckhandKit
import SwiftUI

/// The names this session answers to, to put in front of what you were going to say.
///
/// A phone dictates a sentence well and spells `/orchestrate-sessions` badly. So the name is
/// chosen from a list and the words after it are still spoken — which is the division of labour
/// the whole app is built on, applied to the one part of a prompt that has to be exact.
///
/// There are getting on for two hundred of them on this Mac, so it opens with the field focused
/// and the list narrows as you type. Two hundred rows you scroll is a list nobody opens twice.
struct CommandPicker: View {
    /// Fetched when this appears rather than held by the card: they are files on the Mac that a
    /// person edits, and most cards never ask for one.
    let load: () async -> [SlashCommand]
    let chose: (SlashCommand) -> Void
    @State private var all: [SlashCommand] = []
    @State private var looking = ""
    @State private var asked = false
    @Environment(\.dismiss) private var dismiss

    private var shown: [SlashCommand] { all.filter { $0.matches(looking) } }

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("Commands")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { dismiss() }.tint(Palette.tint)
                    }
                }
        }
        .searchable(text: $looking, prompt: "Name or what it does")
        .task {
            all = await load()
            asked = true
        }
    }

    @ViewBuilder private var list: some View {
        if all.isEmpty {
            // Two different silences: still asking the Mac, or asked and there are none. A
            // spinner that never resolves and an empty folder look identical without this.
            ContentUnavailableView(asked ? "No commands on this Mac" : "Asking the Mac…",
                                   systemImage: asked ? "slash.circle" : "ellipsis")
        } else if shown.isEmpty {
            ContentUnavailableView.search(text: looking)
        } else {
            List(shown) { command in
                Button { chose(command); dismiss() } label: { row(command) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("command-row")
            }
            .listStyle(.plain)
        }
    }

    private func row(_ command: SlashCommand) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            heading(command)
            if !command.description.isEmpty {
                Text(command.description)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }

    private func heading(_ command: SlashCommand) -> some View {
        HStack(spacing: Spacing.extraSmall) {
            Text(command.typed)
                .font(Typography.mono)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            // What to say after it, where it says. The one piece of this that changes what you
            // dictate next, so it sits on the same line as the name rather than below.
            if !command.hint.isEmpty {
                Text(command.hint)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            // Only the ones that are not the ordinary case. A caption reading "user command" on
            // 190 rows is a column of noise; "project" is the one worth noticing, because it
            // means this folder and not the Mac.
            if command.scope == "project" { tag("project") }
            if command.isSkill { tag("skill") }
        }
    }

    /// The word alone in the quiet colour — no capsule. A badge here would read as something to
    /// press, on a row that is entirely something to press.
    private func tag(_ word: String) -> some View {
        Text(word.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(Palette.textTertiary)
    }
}
