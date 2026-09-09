import DeckhandKit
import SwiftUI

/// What the session ran between one message and the next, as a row of dots.
///
/// A busy turn can carry fifty tool calls. Listed, they bury the words either side of them;
/// as dots they take one line and still say the three things worth knowing at a glance — how
/// much it did, what kind of work it was, and whether any of it failed. Tapping unfolds the
/// list, because the moment you care at all you care about which file and which command.
struct ToolTrace: View {
    let tools: [Tool]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            Button { open.toggle() } label: { dots }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tool-trace")
                .accessibilityLabel("\(tools.count) tool calls")
            if open {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(tools) { line($0) }
                }
                .padding(.leading, Spacing.xxs)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, Spacing.extraSmall)
        .padding(.vertical, Spacing.xxs)
        .animation(.snappy(duration: 0.18), value: open)
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                Circle()
                    .fill(colour(tool))
                    .frame(width: 6, height: 6)
            }
            Text(open ? "hide" : summary)
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
                .padding(.leading, Spacing.xxs)
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }

    /// Failures are the reason to look, so they are what the closed row says.
    private var summary: String {
        let failed = tools.filter { !$0.succeeded }.count
        if failed > 0 { return "\(tools.count) steps · \(failed) failed" }
        return tools.count == 1 ? "1 step" : "\(tools.count) steps"
    }

    private func line(_ tool: Tool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.extraSmall) {
            Circle()
                .fill(colour(tool))
                .frame(width: 6, height: 6)
            Text(tool.name)
                .font(Typography.cardLabel)
                .foregroundStyle(Palette.textSecondary)
            Text(tool.detail)
                .font(Typography.mono)
                .foregroundStyle(tool.succeeded ? Palette.textTertiary : Palette.lcdRed)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    /// A failure is red whatever it was doing: that is the one thing worth breaking the
    /// colour scheme for.
    private func colour(_ tool: Tool) -> Color {
        guard tool.succeeded else { return Palette.lcdRed }
        switch tool.kind {
        case .reading: return Palette.textTertiary
        case .changing: return Palette.tint
        case .running: return Palette.lcdGreen
        case .asking: return Palette.lcdYellow
        case .other: return Palette.textTertiary
        }
    }
}
