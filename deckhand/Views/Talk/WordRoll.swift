import DeckhandKit
import SwiftUI

/// One word taking another's place inside a control that does not move.
///
/// The pill carried `.id(word)`, which tore the whole capsule down and built a new one for every
/// word — `Palette.lcdGround` fill, shadow and all. With one word for a whole wait nobody saw it;
/// with six narration beats it was the button flashing in and out six times. So the capsule is a
/// fixed thing now and this is the only part of it that changes.
///
/// **Which word owns the layout is the whole trick.** The word coming *in* does — it is the
/// hidden `Text` this view is sized from — and the pair actually being animated hangs off it as an
/// overlay, out of layout entirely. So from the first frame of a swap the container is already the
/// new word's width: the capsule makes one smooth resize rather than settling after the letters
/// land, and in the staggered style every incoming letter is laid out where it will finally sit
/// instead of travelling sideways into place. The mark beside it cannot be shoved either way —
/// each wing is a `maxWidth: .infinity` half and the pill grows about its own centre inside it.
///
/// The room around the word is here rather than on the pill because the mask depends on it: a
/// word has to slide out under the capsule's own edge, not under an invisible wall a few points
/// inside it.
struct WordRoll: View {
    let word: String
    let tint: Color
    /// Whether the letters roll one at a time. Off is the whole word sliding across.
    var letters = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = ""
    /// True only while a word is actually crossing an edge. The feathered ends are a transition
    /// effect: a pill at rest must not look torn off, and every other pill in this app has hard
    /// edges. When it is false the mask is a plain rectangle, which is still a clip — so a letter
    /// can never draw outside the capsule even if this flag drops early.
    @State private var swapping = false

    /// How much of each end the word fades through. A fraction rather than a number of points, so
    /// it stays proportionate across `CANCEL` and `RELEASE TO PREVIEW`.
    private static let edge = 0.16

    /// How far a letter travels on its way out or in. Far enough to read as a roll, near enough
    /// that it is gone inside the pill's own 6pt of vertical room.
    private static let rise: CGFloat = 9

    var body: some View {
        Text(shown)
            .hidden()
            .overlay { roll.fixedSize() }
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, 6)
            .mask { if swapping { feather } else { Rectangle() } }
            .font(Typography.state)
            .trackedCentred(1.4)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            // The first word arrives with the capsule's own transition and must not roll: there is
            // nothing for it to replace, and a roll from an empty string is a word falling out of
            // the ceiling for no reason.
            .onAppear { shown = word }
            .onChange(of: word) { _, next in swap(to: next) }
    }

    @ViewBuilder private var roll: some View {
        if letters && !reduceMotion { rolled } else { slid }
    }

    /// The whole word across. Out to the leading edge, in from the trailing one, because the
    /// beats advance and a word arriving from the side the last one left by reads as a flicker
    /// rather than as progress.
    private var slid: some View {
        ZStack {
            Text(shown)
                .id(shown)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)))
        }
    }

    /// A letter at a time, in reading order, every one of them travelling the same way: the old
    /// word's letters go up and out and the new word's come up from below into place, so it reads
    /// as one roll rather than as two unrelated moves.
    private var rolled: some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { spot, letter in
                    Text(String(letter))
                        .transition(.asymmetric(insertion: arrives(spot),
                                                removal: departs(spot)))
                }
            }
            .id(shown)
        }
    }

    private func arrives(_ spot: Int) -> AnyTransition {
        .offset(y: Self.rise).combined(with: .opacity).animation(rolling(spot))
    }

    private func departs(_ spot: Int) -> AnyTransition {
        .offset(y: -Self.rise).combined(with: .opacity).animation(rolling(spot))
    }

    private func rolling(_ spot: Int) -> Animation {
        Motion.letter.delay(Double(spot) * Motion.stagger)
    }

    /// Soft at both ends, so a word reads as sliding under the edge rather than being cut off at
    /// one. `SessionView.edges` is the same idiom stood upright, softening where a pane's content
    /// runs off the top and bottom of the screen; this is it on its side and only while something
    /// is crossing.
    private var feather: some View {
        LinearGradient(stops: [.init(color: .clear, location: 0),
                               .init(color: .black, location: Self.edge),
                               .init(color: .black, location: 1 - Self.edge),
                               .init(color: .clear, location: 1)],
                       startPoint: letters ? .top : .leading,
                       endPoint: letters ? .bottom : .trailing)
    }

    /// Reduce Motion gets the crossfade and none of the travel — a sixteen-letter roll is exactly
    /// what that setting exists for. Still `Motion.word` rather than a slower fade: the ceiling is
    /// the next beat, and it does not move for anybody's preferences.
    private func swap(to next: String) {
        swapping = true
        withAnimation(Motion.word, completionCriteria: .removed) {
            shown = next
        } completion: {
            swapping = false
        }
    }
}
