import DeckhandKit
import SwiftUI

/// One row of the tray's history: an answer, a call, or a stretch of a session's finished work.
/// The whole row opens that session.
struct TrayHistoryRow: View {
    let item: TrayItem
    /// Newer than the last time the tray was open. Drawn by the eyebrow's colour and nothing
    /// else — no badge, no dot.
    let fresh: Bool
    let onOpen: (String) -> Void

    var body: some View {
        Button { onOpen(session) } label: {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.xxs) {
                    Text(word)
                        .font(Typography.eyebrow)
                        .tracking(1)
                        .foregroundStyle(fresh ? tone : Palette.textTertiary)
                    Text(name)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: Spacing.extraSmall)
                    Text(moment, format: .relative(presentation: .named))
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
                content
            }
            .padding(.vertical, Spacing.small)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var content: some View {
        switch item {
        case .update(let update) where update.kind == .answered:
            Text(update.title ?? update.slip ?? "A slip")
                .font(Typography.prose)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(2)
            Label(update.answer ?? "Answered", systemImage: "arrow.turn.down.right")
                .font(Typography.primaryRow)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
        case .update(let update):
            Text(update.line ?? "")
                .font(Typography.prose)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(3)
        case .work(let work):
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                ForEach(work.asks, id: \.self) { ask in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.extraSmall) {
                        AskDot(state: .done, size: 9)
                        Text(ask)
                            .font(Typography.prose)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private var session: String {
        switch item {
        case .update(let update): update.session
        case .work(let work): work.session
        }
    }

    private var name: String {
        switch item {
        case .update(let update): update.name
        case .work(let work): work.name
        }
    }

    private var moment: Date {
        switch item {
        case .update(let update): update.moment
        case .work(let work): work.moment
        }
    }

    /// The kind, as one word: what was answered, who called, and how far a stretch of work got.
    private var word: String {
        switch item {
        case .update(let update):
            switch update.kind {
            case .answered: "ANSWERED"
            case .called: "CALLED"
            case .blocked: "WAITING"
            default: "UPDATE"
            }
        case .work(let work): work.cleared ? "ALL DONE" : "DONE"
        }
    }

    private var tone: Color {
        switch item {
        case .update(let update): update.kind == .answered ? Palette.tint : Palette.lcdYellow
        case .work: Palette.lcdGreen
        }
    }
}
