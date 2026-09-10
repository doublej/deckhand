import DeckhandKit
import SwiftUI

/// Say the rest of it, under the words the card is already holding.
///
/// It sits under the prompt rather than in the row at the foot, which is where it started. The
/// four down there are what you do *with* what the card holds — throw it away, change it, send it
/// — and this one makes more of it; standing among them it read as a fourth verb of the same
/// kind, and the row was one control too wide either way. Under the words is where the words it
/// records are going to land, which is the whole of what it needs to say.
///
/// It is `TalkControl` underneath, so hold-versus-tap is the same gesture it is everywhere else in
/// the app, and `Appending.swift` is what puts the words beneath rather than over.
struct SayRest: View {
    let more: SayMore
    /// The words as they stand, which is what a second clip lands beneath.
    let words: String
    /// Called once the clip has been handed over, so the card can drop the draft it just passed
    /// up: the new words come back as the model's, and a stale draft would mask them.
    let finished: () -> Void
    @Environment(\.accent) private var accent

    /// The minimum a finger can be asked to hit. The same raw number `ReviewActions`, `SayInto`
    /// and `FilesView` write, and for the same reason: no spacing token means "a finger".
    private static let touch: CGFloat = 44

    var body: some View {
        TalkControl(recorder: more.recorder,
                    mode: more.mode,
                    isMine: true,
                    onStart: {},
                    onClip: { clip in
                        await more.heard(clip, words)
                        finished()
                    },
                    content: { face($0) })
    }

    /// While it listens the capsule fills, and once the clip is on the wire it spins.
    ///
    /// A glyph beside the word now that it stands on its own. In the row at the foot it was one
    /// verb among four and read as one; alone under a prompt, "Add" on its own could be adding
    /// anything, and the microphone is the whole of the difference.
    private func face(_ state: TalkState) -> some View {
        let live = state.isRecording || state.busy
        return HStack(spacing: Spacing.xxs) {
            if state.busy {
                ProgressView().controlSize(.mini).tint(.white)
            } else {
                Image(systemName: state.isRecording ? "mic.fill" : "mic")
            }
            Text(word(state))
        }
        .font(.system(size: 14))
        .foregroundStyle(live ? Color.white : accent)
        .lineLimit(1)
        .padding(.horizontal, Spacing.small)
        .frame(minHeight: Self.touch)
        .background(Capsule().fill(fill(state)))
        .contentShape(.capsule)
        .animation(.snappy(duration: 0.2), value: word(state))
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(spoken(state))
        .accessibilityIdentifier("say-rest")
    }

    /// What the next press does, said only when a press is what comes next.
    ///
    /// The word used to be "Add" throughout, and the reasoning was sound for half the cases: in
    /// hold mode the finger is on the capsule, so nothing about it may change size — that is the
    /// failure `TalkMark` records having made once already. In tap mode the finger is off it and
    /// a second tap is exactly what ends the recording, so a control that still says "Add" is
    /// refusing to say the one thing the person needs to know.
    ///
    /// And then the clip goes to the Mac to be transcribed, which takes seconds and said nothing
    /// at all — so it says that too, rather than leaving somebody to wonder whether the tap
    /// landed and press it again.
    private func word(_ state: TalkState) -> String {
        if state.busy { return "Adding…" }
        return state.isRecording && state.mode == .toggle ? "Done" : "Add"
    }

    private func fill(_ state: TalkState) -> Color {
        if state.isRecording { return accent }
        // Still filled, dimmed: the clip is on the wire and the words are a moment away, which is
        // neither still listening nor nothing happening.
        if state.busy { return accent.opacity(0.45) }
        return Palette.tileIdle
    }

    private func spoken(_ state: TalkState) -> String {
        if state.busy { return "Transcribing what you added" }
        let what = state.mode == .hold ? "let go" : "tap again"
        if state.isRecording { return "Recording, \(what) to add it under these words" }
        return state.mode == .hold ? "Hold to add to these words" : "Tap to add to these words"
    }
}
