import DeckhandKit
import SwiftUI

/// What the clip in the review card cost: one line under the row you press, and the stages on a
/// slab that slides out from under the card.
///
/// It is a receipt, not a fourth thing to do with the prompt, so the line stays quiet and stays
/// below Discard, Edit and Send: the round trip at rest with the slowest stage beside it, because
/// that is the whole of what a person wants while reading their own words back — is this normal,
/// and if it is not, which end was it.
///
/// **The stages are not drawn inside the card.** They were, and before that they were a sheet.
/// The sheet was wrong for a reason that still holds — it took the card off the screen in order to
/// explain the card — but drawing fourteen rows *inside* the card was the other failure: the card
/// is the prompt you are about to send, and it grew to twice its height with a table of
/// milliseconds in it. So the breakdown gets a container of its own, on the page rather than in
/// the card, and it arrives by sliding down out from under it. Same ground, no accent border: a
/// plainer slab that is clearly the same family and clearly not the thing you are sending.
struct ClipCost: View {
    let timing: ClipTiming
    @State private var breakdown = false
    /// How tall the stages are, measured off the copy that is always laid out. The slab's height
    /// animates between 0 and this, and there is no other way to know it: the table is as tall as
    /// however many stages this clip has, and a guessed height would clip the last row on the one
    /// clip that had something interesting to say. `WordRoll` sizes itself the same way.
    @State private var tall: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(Motion.opening) { breakdown.toggle() } } label: { line }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clip-cost")
                .accessibilityLabel("Round trip \(TimingsView.spelled(timing.total))")
                .accessibilityHint(breakdown ? "Hides the stages" : "Shows it stage by stage")
            slab
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

    /// The slab, and the whole of the sliding.
    ///
    /// Three modifiers doing one thing: the slot is `0` tall when shut and `tall` when open, the
    /// stages sit `-tall` above their slot when shut, and `.clipped()` means the part standing
    /// outside the slot is not drawn. Opening grows the slot and walks the offset back to zero at
    /// the same time, under one `Motion.opening`, so the stages appear to be pulled downward out
    /// from beneath whatever is above them rather than to be revealed in place.
    ///
    /// The copy is always laid out — that is what keeps `tall` honest — so it is hidden from
    /// VoiceOver and from the hit-testing while it is shut, or a shut slab would still be read out
    /// and still take taps through the card below it.
    private var slab: some View {
        stages
            // Before the frame below, and load-bearing: that frame proposes 0 points of height
            // while the slab is shut, and a VStack of text handed a 0 proposal reports back 0.
            // `tall` would measure zero, stick there, and the slab would never open again.
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tall = $0 }
            .offset(y: breakdown ? 0 : -tall)
            .frame(height: breakdown ? tall : 0, alignment: .top)
            .clipped()
            .allowsHitTesting(breakdown)
            .accessibilityHidden(!breakdown)
    }

    private var stages: some View {
        // Without the total over it: the line above is that number, and printing it twice eight
        // points apart says nothing the first one did not.
        TimingsView(timing: timing, compact: true, totalled: false)
            .padding(Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .fill(Palette.surfacePrimary)
            )
            .padding(.top, Spacing.xxs)
    }
}
