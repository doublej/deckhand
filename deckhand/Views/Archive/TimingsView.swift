import DeckhandKit
import SwiftUI

/// What one clip cost, stage by stage, in milliseconds.
///
/// Exact numbers, because a bar chart with no numbers cannot answer the question this is opened
/// to answer — which stage is the slow one, and by how much. The bars are only there so the
/// answer can be found without reading fourteen numbers first.
///
/// Two surfaces show it and both are pages: a row in the clip archive that expands, and the
/// sheet behind the total on the review card. Nothing here sets a ground of its own.
struct TimingsView: View {
    let timing: ClipTiming
    /// The archive draws it inside a list row that is already tight.
    var compact = false

    private var longest: Double { max(timing.slowest?.took ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            heading
            ForEach(Array(timing.stages.enumerated()), id: \.element.id) { spot, stage in
                row(stage, under: spot == 0 ? nil : timing.stages[spot - 1].side)
            }
            if let note = timing.stages.first(where: { $0.note != nil })?.note {
                Text(note)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.xxs)
            }
        }
    }

    /// The two numbers worth reading first: the whole of it, and how much of the wait was the
    /// person talking. Talking is not a cost and is kept out of the total for that reason —
    /// a breakdown dominated by however long somebody spoke says nothing about what is slow.
    private var heading: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Text("PRESS TO CARD")
                    .font(Typography.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(Palette.textTertiary)
                Spacer(minLength: 0)
                Text(Self.spelled(timing.total))
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textPrimary)
            }
            Text("\(Self.spelled(timing.spoken)) of it was talking")
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.bottom, Spacing.extraSmall)
    }

    /// One stage. The side is named only where it changes, or the column reads PHONE PHONE
    /// PHONE and says nothing.
    private func row(_ stage: Stage, under previous: Stage.Side?) -> some View {
        HStack(spacing: Spacing.extraSmall) {
            Text(stage.side == previous ? "" : stage.side.rawValue.uppercased())
                .font(Typography.eyebrow)
                .tracking(1.0)
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 34, alignment: .leading)
            Text(stage.title)
                .font(compact ? Typography.hint : Typography.prose)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Spacing.extraSmall)
            Text(Self.spelled(stage.took))
                .font(Typography.mono)
                .foregroundStyle(stage == timing.slowest ? Palette.lcdRed : Palette.textSecondary)
        }
        .padding(.vertical, 1)
        .background(alignment: .leading) { bar(stage) }
    }

    /// How much of the wait this stage was, drawn behind the words rather than beside them:
    /// the numbers are the content and a chart column would push them off a phone.
    private func bar(_ stage: Stage) -> some View {
        GeometryReader { space in
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Palette.tint.opacity(0.14))
                .frame(width: space.size.width * (stage.took / longest))
        }
    }

    /// Milliseconds up to a second, then seconds. A five-digit millisecond count is a number
    /// nobody reads as a length of time.
    static func spelled(_ took: Double) -> String {
        took < 1000 ? "\(Int(took.rounded())) ms" : String(format: "%.2f s", took / 1000)
    }
}
