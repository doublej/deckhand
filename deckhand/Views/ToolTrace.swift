import DeckhandKit
import SwiftUI

/// What the session ran between one message and the next, at whichever depth you want it.
///
/// Three states, because there are three genuinely different questions. Did it do much, and
/// did anything break — that is a row of dots. Which files, which commands — that is a list.
/// What exactly did it run and what came back — that is everything, and it is what you want
/// perhaps once a day, so it is two taps away rather than on the screen by default.
struct ToolTrace: View {
    let tools: [Tool]
    @State private var depth: Depth = .dots

    enum Depth {
        case dots, list, everything

        /// Tapping walks forward and wraps, so one control reaches all three and gets home.
        var next: Depth {
            switch self {
            case .dots: .list
            case .list: .everything
            case .everything: .dots
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            Button { depth = depth.next } label: { head }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tool-trace")
            if depth != .dots {
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    ForEach(tools) { row($0) }
                }
                .padding(.leading, Spacing.xxs)
            }
        }
        .padding(.horizontal, Spacing.extraSmall)
        .padding(.vertical, Spacing.xxs)
        .animation(.snappy(duration: 0.18), value: depth)
    }

    /// The dots are the closed state's whole content. Once the list is open they are stacked
    /// down the left of it, one per row, so repeating them across the top says nothing twice.
    private var head: some View {
        HStack(spacing: 5) {
            if depth == .dots {
                ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                    Circle().fill(colour(tool)).frame(width: 6, height: 6)
                }
            }
            Text(label)
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
                .padding(.leading, depth == .dots ? Spacing.xxs : 0)
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }

    /// Failures are the reason to look, so the closed row leads with them.
    private var label: String {
        let failed = tools.filter { !$0.succeeded }.count
        let count = tools.count == 1 ? "1 step" : "\(tools.count) steps"
        switch depth {
        case .dots: return failed > 0 ? "\(count) · \(failed) failed" : count
        case .list: return "\(count) · tap for the full call"
        case .everything: return "\(count) · tap to close"
        }
    }

    @ViewBuilder private func row(_ tool: Tool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
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
                    .lineLimit(depth == .everything ? 1 : 2)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            if depth == .everything { whole(tool) }
        }
    }

    /// Selectable, because the reason to open a tool call on a phone is usually to get a path
    /// or an error string off it and into somewhere else.
    @ViewBuilder private func whole(_ tool: Tool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            if !tool.call.isEmpty { block("CALL", tool.call, Palette.textSecondary) }
            if !tool.result.isEmpty {
                block(tool.succeeded ? "RESULT" : "FAILED", tool.result,
                      tool.succeeded ? Palette.textSecondary : Palette.lcdRed)
            }
        }
        .padding(.leading, Spacing.small)
    }

    private func block(_ title: String, _ body: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Typography.eyebrow)
                .tracking(1)
                .foregroundStyle(tint)
            Text(body)
                .font(Typography.mono)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.extraSmall)
        .background(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(Palette.tileIdle)
        )
    }

    /// A failure is red whatever it was doing: the one thing worth breaking the scheme for.
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
