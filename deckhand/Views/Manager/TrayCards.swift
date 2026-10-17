import DeckhandKit
import SwiftUI

/// One session that needs you: who it is, what it called for you about, and each slip it left,
/// asked in place.
struct AttentionCard: View {
    @Bindable var model: AppModel
    let row: TraySession
    let open: (TraySlip) -> Void

    var body: some View {
        Card(spacing: Spacing.small) {
            head
            if let line = row.waiting, !line.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("ASKED FOR YOU")
                        .font(Typography.eyebrow)
                        .tracking(1)
                        .foregroundStyle(Palette.lcdYellow)
                    Text(line)
                        .font(Typography.prose)
                        .foregroundStyle(Palette.textPrimary)
                }
            }
            ForEach(Array(row.slips.enumerated()), id: \.element.id) { index, slip in
                if index > 0 || !(row.waiting ?? "").isEmpty { Hairline() }
                SlipQuestion(model: model, row: row, slip: slip) { open(slip) }
            }
        }
    }

    /// The session's face, name and machine. The whole row opens its page, which is where a call
    /// is answered — by saying something to it.
    private var head: some View {
        Button { Task { await model.goTo(session: row.session) } } label: {
            HStack(spacing: Spacing.extraSmall) {
                GlyphTile(DotGlyph.forName(row.name), size: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.name)
                        .font(Typography.primaryRow)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let machine = row.machine, !machine.isEmpty {
                        Text(machine)
                            .font(Typography.hint)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                Spacer(minLength: Spacing.extraSmall)
                StateWord(.wait)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(row.name)")
    }
}

/// One slip, asked the way its kind asks: two buttons, a list of rows, a field, or the page.
struct SlipQuestion: View {
    @Bindable var model: AppModel
    let row: TraySession
    let slip: TraySlip
    let open: () -> Void
    @State private var sending = false
    @State private var failure: String?
    @State private var typed = ""
    @Environment(\.accent) private var accent

    /// A finger, as `WaitingSlip` spells it.
    private static let target: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            Text(slip.title)
                .font(Typography.prose.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            answers
                .disabled(sending)
                .opacity(sending ? 0.5 : 1)
            if sending {
                Text("Sending…").font(Typography.hint).foregroundStyle(Palette.textSecondary)
            } else if let failure {
                Text(failure).font(Typography.hint).foregroundStyle(Palette.lcdRed)
            }
        }
    }

    @ViewBuilder private var answers: some View {
        switch slip.ask.kind {
        case .confirm:
            HStack(spacing: Spacing.extraSmall) {
                choice(slip.ask.decline ?? "No", filled: false) { send(SlipAsk.answer(false)) }
                choice(slip.ask.accept ?? "Yes", filled: true) { send(SlipAsk.answer(true)) }
            }
        case .pick:
            VStack(spacing: Spacing.xxs) {
                ForEach(slip.ask.options ?? [], id: \.self) { option in
                    row(option, symbol: "circle") { send(SlipAsk.answer(option)) }
                }
                if slip.ask.other == true { row("Something else…", symbol: "ellipsis", act: open) }
            }
        case .text:
            HStack(spacing: Spacing.extraSmall) {
                TextField(slip.ask.label ?? "Answer", text: $typed, axis: .vertical)
                    .font(Typography.prose)
                    .lineLimit(1...4)
                    .padding(.horizontal, Spacing.extraSmall)
                    .padding(.vertical, Spacing.xxs + 2)
                    .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(Palette.textPrimary.opacity(0.06)))
                Button("Send", systemImage: "arrow.up") { send(SlipAsk.answer(words)) }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 13, weight: .semibold))
                    .disabled(words.isEmpty)
            }
        case .aloud:
            row("Answer aloud", symbol: "waveform", act: open)
        case .page:
            row("Open the slip", symbol: "doc.richtext", act: open)
        }
    }

    private var words: String { typed.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A confirm's button. Yes is the filled one and sits last, where a thumb ends up — the Lock
    /// Screen card's order. Ink on the teal is `lcdGround`, which reads at 5:1 where white is 2.6.
    private func choice(_ title: String, filled: Bool, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(title)
                .font(Typography.primaryRow)
                .lineLimit(1)
                .foregroundStyle(filled ? Palette.lcdGround : Palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: Self.target)
                .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(filled ? accent : Palette.tileIdle))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A pick's row, and the way to a page: the words leading, the mark trailing.
    private func row(_ title: String, symbol: String, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: Spacing.extraSmall) {
                Text(title)
                    .font(Typography.primaryRow)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Spacing.extraSmall)
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, Spacing.small)
            .frame(maxWidth: .infinity, minHeight: Self.target)
            .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(Palette.tileIdle))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One tap, one answer: the controls stand down while it is in flight, because a second press
    /// is a second answer into the session.
    private func send(_ json: String) {
        sending = true
        failure = nil
        Task {
            failure = await model.answerSlip(slip, of: row, valueJSON: json)
            sending = false
        }
    }
}
