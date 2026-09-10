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
/// And directly under them now, not at the foot of a box the words did not fill: it is where the
/// caret would be, because `Appending` lays the next clip on the line beneath these. The gap was
/// the words' scroll box taking every point the card was offered; the card hugs them instead.
///
/// It is `TalkControl` underneath, so hold-versus-tap is the same gesture it is everywhere else in
/// the app, and `Appending.swift` is what puts the words beneath rather than over.
struct SayRest: View {
    let more: SayMore
    /// The words as they stand, which is what a second clip lands beneath.
    let words: String
    /// True from the moment the clip goes to the Mac until its words are back.
    ///
    /// `TalkControl` keeps this state privately for its own label, and the card outside needs the
    /// same fact for a different reason: Send must not be pressable while a sentence is still in
    /// the air. Reported rather than read, because it is set around an `await` in an action
    /// closure — the one place a view may change state without doing it mid-render.
    @Binding var adding: Bool
    /// Called once the clip has been handed over, so the card can drop the draft it just passed
    /// up: the new words come back as the model's, and a stale draft would mask them.
    let finished: () -> Void
    @Environment(\.accent) private var accent

    /// The minimum a finger can be asked to hit. The same raw number `ReviewActions`, `SayInto`
    /// and `FilesView` write, and for the same reason: no spacing token means "a finger".
    ///
    /// Here it is the *target* only and no longer the drawn size — see `face`.
    private static let touch: CGFloat = 44

    var body: some View {
        TalkControl(recorder: more.recorder,
                    mode: more.mode,
                    isMine: true,
                    onStart: {},
                    onClip: { clip in
                        adding = true
                        await more.heard(clip, words)
                        adding = false
                        finished()
                    },
                    content: { face($0) })
    }

    /// While it listens it fills, and once the clip is on the wire it spins.
    ///
    /// A glyph beside the word now that it stands on its own. In the row at the foot it was one
    /// verb among four and read as one; alone under a prompt, "Add" on its own could be adding
    /// anything, and the microphone is the whole of the difference.
    ///
    /// **It is drawn small and left unfilled at rest.** It used to be a 14pt word in a filled
    /// 44pt tile, which is the size and weight of the buttons that send and discard — and it is
    /// not one of those. It makes more of the prompt; they finish it. Two rows above it,
    /// `ReviewCard`'s own Command and Add-attachments controls are `Typography.hint` in the
    /// accent with nothing behind them, and they are the same kind of thing as this one: part of
    /// writing a prompt rather than something you do with a written one. So it looks like them.
    ///
    /// **The ink shrank; the target did not.** The fill and the words sit inside a 44pt frame
    /// whose `contentShape` is the whole of it, so a finger still lands on 44 points even though
    /// far less than that is drawn — which matters more here than anywhere else in the card,
    /// because in hold mode the finger stays on this control for the length of the clip.
    ///
    /// A capsule, now that it is small and outside everything: the corner that used to clash was
    /// a 22pt one nested inside the card, and nothing about a 24pt chip is nested in anything.
    private func face(_ state: TalkState) -> some View {
        HStack(spacing: Spacing.xxs) {
            if state.busy {
                ProgressView().controlSize(.mini).tint(.white)
            } else {
                Image(systemName: state.isRecording ? "mic.fill" : "mic")
            }
            Text(word(state))
        }
        .font(Typography.hint)
        .foregroundStyle(fill(state) == .clear ? accent : Color.white)
        .lineLimit(1)
        .chip(fill(state))
        // Pulled back by exactly the padding inside it, so the microphone starts on the same
        // vertical as the first letter of the prompt above rather than eight points in. The
        // padding stays: it is what stops the capsule cutting into the glyph while recording,
        // and this is the one card where a control indented from the words it continues reads
        // as belonging to something else.
        .padding(.leading, -Chip.insets.leading)
        // Bottom-aligned inside the 44, not centred in it. An 11pt word centred in a 44pt box
        // has fifteen points of air under it, and on the foot row of a card that air read as
        // the card being bottom-heavy — the words looked stranded above their own edge. The
        // finger keeps all 44 points; the box simply grows upward into the gap above the row,
        // which was slack anyway.
        .frame(minHeight: Self.touch, alignment: .bottomLeading)
        .contentShape(.rect)
        .animation(Motion.word, value: word(state))
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(spoken(state))
        .accessibilityIdentifier("say-rest")
    }

    /// What the next press does, said only when a press is what comes next.
    ///
    /// The word used to be "Add" throughout, and the reasoning was sound for half the cases: in
    /// hold mode the finger is on the control, so nothing about it may change size — that is the
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

    /// Nothing at rest, and the accent the moment it is doing something.
    ///
    /// The resting tile is gone with the rest of the weight: a filled chip under a prompt reads
    /// as a button you are meant to press next, and this one is optional. Recording and sending
    /// still fill, because that is not decoration — it is the only thing on screen saying the
    /// microphone is open, and a control that goes quiet while listening is the one failure this
    /// cannot have.
    private func fill(_ state: TalkState) -> Color {
        if state.isRecording { return accent }
        // Still filled, dimmed: the clip is on the wire and the words are a moment away, which is
        // neither still listening nor nothing happening.
        if state.busy { return accent.opacity(0.45) }
        return .clear
    }

    private func spoken(_ state: TalkState) -> String {
        if state.busy { return "Transcribing what you added" }
        let what = state.mode == .hold ? "let go" : "tap again"
        if state.isRecording { return "Recording, \(what) to add it under these words" }
        return state.mode == .hold ? "Hold to add to these words" : "Tap to add to these words"
    }
}
