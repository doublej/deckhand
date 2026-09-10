import DeckhandKit
import SwiftUI

/// What one clip cost, stage by stage, in milliseconds.
///
/// Exact numbers, because a bar chart with no numbers cannot answer the question this is opened
/// to answer — which stage is the slow one, and by how much. The bars are only there so the
/// answer can be found without reading fourteen numbers first.
///
/// Two surfaces show it and both are pages, and both open it in place rather than over
/// themselves: a row in the clip archive, and the round-trip line under the review card's
/// buttons. Nothing here sets a ground of its own.
struct TimingsView: View {
    let timing: ClipTiming
    /// The archive draws it inside a list row that is already tight.
    var compact = false
    /// The total, over the table. Off where whatever opened this is already showing it — the
    /// review card's own line *is* the total, and the same number twice is not a second fact.
    var totalled = true

    private var longest: Double { max(timing.slowest?.took ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            heading
            ForEach(Array(timing.stages.enumerated()), id: \.element.id) { spot, stage in
                row(stage, under: spot == 0 ? nil : timing.stages[spot - 1].side)
                // utt's span opens into the stretches utt measured, indented under it. A utt
                // that measures nothing has no children and the span stays one row, which is
                // the degraded case rather than the shape this is built around.
                ForEach(stage.children) { child in inner(child) }
            }
            asides
        }
    }

    /// The sentences that belong under the table rather than in it.
    @ViewBuilder private var asides: some View {
        let notes = timing.stages.flatMap { [$0] + $0.children }.compactMap(\.note)
        ForEach(notes + [timing.cleanupNote].compactMap { $0 }, id: \.self) { note in
            Text(note)
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Spacing.xxs)
        }
    }

    /// One of utt's own stages, inside utt's span.
    ///
    /// The verdict beside it is the other half of the record and not the same question: the
    /// number says a stage ran, `stages` says whether it changed anything, and utt reports them
    /// separately on purpose. "Cleanup ran, 900 ms, unchanged" is a sentence that did not exist
    /// before utt measured itself, and it is the one worth having.
    private func inner(_ stage: Stage) -> some View {
        HStack(spacing: Spacing.extraSmall) {
            Text(stage.titleInsideUtt)
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            if let verdict = timing.verdict(on: stage) {
                Text(verdict)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.extraSmall)
            Text(Self.spelled(stage.took))
                .font(Typography.mono)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.leading, Spacing.large)
        .padding(.vertical, 1)
    }

    /// The two numbers worth reading first: the whole of it, and how much of the wait was the
    /// person talking. Talking is not a cost and is kept out of the total for that reason —
    /// a breakdown dominated by however long somebody spoke says nothing about what is slow.
    private var heading: some View {
        VStack(alignment: .leading, spacing: 1) {
            if totalled {
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
            }
            Text(pace)
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.bottom, Spacing.extraSmall)
    }

    /// How long the wait was against how long the person talked. The one line here that says
    /// whether a number is good, rather than only what it was: half a second is fine for a
    /// sentence and poor for a word.
    ///
    /// Off the clip's own length as this phone recorded it, which every clip has. utt counts the
    /// audio too and sends it as `duration`, but only on a utt new enough to — and this phone
    /// already knows, so waiting for the Mac to say would be worse for no gain.
    private var pace: String {
        let spoken = Self.spelled(timing.spoken)
        guard timing.spoken > 0 else { return "\(spoken) of it was talking" }
        return "\(spoken) of it was talking · \(String(format: "%.1f", timing.total / timing.spoken))× that again waiting"
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
