import DeckhandKit
import SwiftUI

/// What the clip in the review card cost, as one line under the row you press.
///
/// It is a receipt, not a fourth thing to do with the prompt, so it sits *below* Discard, Edit and
/// Send and stays quiet: the round trip at rest with the slowest stage beside it, because that is
/// the whole of what a person wants while reading their own words back — is this normal, and if it
/// is not, which end was it.
///
/// The breakdown opens in place. It used to be a sheet, which took the card off the screen in order
/// to explain the card; fourteen numbers about the thing you are still holding belong inside it.
/// `ClipRow` in the archive opens the same view the same way, and this is that arrangement.
struct ClipCost: View {
    let timing: ClipTiming
    @State private var breakdown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { breakdown.toggle() } label: { line }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clip-cost")
                .accessibilityLabel("Round trip \(TimingsView.spelled(timing.total))")
                .accessibilityHint(breakdown ? "Hides the stages" : "Shows it stage by stage")
            if breakdown {
                // Without the total over it: the line above is that number, and printing it
                // twice eight points apart says nothing the first one did not.
                TimingsView(timing: timing, compact: true, totalled: false)
                    .padding(.top, Spacing.xxs)
            }
        }
    }

    /// Named rather than left as a bare number. Under the buttons it has no words above it to be
    /// read against, so "29.24 s ›" on its own is a quantity of nothing in particular.
    private var line: some View {
        HStack(spacing: Spacing.xxs) {
            Text("Round trip \(TimingsView.spelled(timing.total))")
            if let slowest = timing.slowest, !breakdown {
                Text("· \(slowest.title.lowercased()) \(TimingsView.spelled(slowest.took))")
                    .foregroundStyle(Palette.textTertiary)
            }
            Image(systemName: breakdown ? "chevron.up" : "chevron.down")
                .font(.system(size: 9))
            Spacer(minLength: 0)
        }
        .font(Typography.hint)
        .foregroundStyle(Palette.textTertiary)
        .lineLimit(1)
        .frame(minHeight: 28, alignment: .leading)
        .contentShape(.rect)
    }
}
