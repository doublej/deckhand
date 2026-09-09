import DeckhandKit
import SwiftUI

/// The foot of the review card: where the words are going, and the things you can do about them.
///
/// It was one line of 11pt words eight points apart, Discard close enough to Edit to be taken for
/// it. The rule here is the one `FilesView`'s selector already set: a control is a capsule at the
/// app's reading size with 44pt of finger under it.
///
/// The four share the width equally, which buys two things beyond room. Nothing is squeezed on a
/// narrow phone, and a label that changes under a state cannot move a button out from under a
/// finger — the failure `TalkMark` records having made once already. Discard sits at the far end
/// from Send, which is the actual fix for hitting the wrong one: distance, not a confirmation.
struct ReviewActions: View {
    let route: String
    /// The words as they stand, which is what Send sends and what a second clip lands beneath.
    let words: String
    let discard: () -> Void
    let edit: () -> Void
    let send: (String) -> Void
    /// What it takes to say the rest of it, or nil where there is no recorder to lend.
    var more: SayMore?
    /// Called once a second clip has been handed over, so the card can drop the draft it just
    /// passed up: the new words come back as the model's, and a stale draft would mask them.
    var finished: () -> Void = {}
    /// A deck column, which is 240pt wide and has room for none of this.
    var compact = false
    @Environment(\.accent) private var accent

    /// The minimum a finger can be asked to hit. The same raw number `FilesView` writes, and for
    /// the same reason: no spacing token means "a finger", and rounding it to one that exists
    /// would be picking a number off a list instead of off a hand.
    private static let touch: CGFloat = 44

    var body: some View {
        if compact { tight } else { roomy }
    }

    /// The session page and the overview: room for real controls, so they are real controls.
    private var roomy: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            // Its own line now. Sharing one with the buttons, it was the thing being squeezed
            // when a name got long — and it is the one item here nobody taps.
            Text("→ \(route)")
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
            HStack(spacing: Spacing.xxs) {
                Button(action: discard) {
                    face("Discard", ink: Palette.textSecondary, fill: Palette.tileIdle)
                }
                .buttonStyle(.plain)
                Button(action: edit) {
                    face("Edit", ink: accent, fill: Palette.tileIdle)
                }
                .buttonStyle(.plain)
                if let more { adding(more) }
                Button { send(words) } label: {
                    face("Send", ink: .white, fill: accent, weight: .semibold)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A deck column. Unchanged: 44pt capsules would be taller than the card they sit in.
    private var tight: some View {
        HStack(spacing: Spacing.small) {
            Text("→ \(route)")
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
            Spacer(minLength: Spacing.extraSmall)
            Button("Discard", action: discard)
                .buttonStyle(.plain)
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
            Button("Edit", action: edit)
                .buttonStyle(.plain)
                .font(Typography.hint)
                .foregroundStyle(accent)
            Button("Send") { send(words) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(accent)
        }
    }

    /// Say the rest of it, wearing the same capsule as the buttons either side of it.
    ///
    /// While it listens the capsule fills, which is feedback that costs no width: the label stays
    /// the same word and the segment stays the same size, so the control cannot move under the
    /// finger holding it. The page is going orange at the same time — this is the local half of
    /// the same signal, for the finger that is covering the rest of the screen.
    private func adding(_ more: SayMore) -> some View {
        TalkControl(recorder: more.recorder,
                    mode: more.mode,
                    isMine: true,
                    onStart: {},
                    onClip: { clip in
                        await more.heard(clip, words)
                        finished()
                    },
                    content: { state in
                        face("Add",
                             ink: state.isRecording ? .white : accent,
                             fill: state.isRecording ? accent : Palette.tileIdle)
                    })
    }

    /// One segment. Equal width to its siblings, 44pt tall, and the label centred in it.
    private func face(
        _ label: String,
        ink: Color,
        fill: Color,
        weight: Font.Weight = .regular
    ) -> some View {
        Text(label)
            .font(.system(size: 14, weight: weight))
            .foregroundStyle(ink)
            .lineLimit(1)
            // Only the narrowest phones with the longest word, and shrinking a point beats
            // truncating "Discard" to "Disca…".
            .minimumScaleFactor(0.85)
            .padding(.horizontal, Spacing.extraSmall)
            .frame(maxWidth: .infinity, minHeight: Self.touch)
            .background(Capsule().fill(fill))
            .contentShape(.rect)
    }
}
