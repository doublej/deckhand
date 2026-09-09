import DeckhandKit
import SwiftUI

/// Say it instead of typing it, into one field.
///
/// The one dictation control in the app that is not aimed at a session. Everything else here
/// records in order to *tell* a session something; this records in order to fill in a box — a new
/// name, a word a filter should swap, the two words the transcript got wrong. A phone dictates
/// better than it types, so every field that can reach the Mac offers this beside it.
///
/// It is `TalkControl` underneath, so hold-versus-tap is the same gesture it is everywhere else and
/// there is no second recorder anywhere in this app. What is different is only where the words
/// land: `Underneath.words` puts them after whatever the field already holds and never over it.
///
/// The words go in at the end rather than at the caret, because SwiftUI on iOS 18 hands out no
/// insertion point for a `TextField` or a `TextEditor` — there is nothing to read and nothing to
/// write back. The end is the honest version of that: everything typed stays, in the order it
/// arrived, and the fix for a word in the middle is the keyboard that is already up.
///
/// What it records and where the words go are two things, and the seam between them is the second
/// initialiser: this view holds a closure, and the field is one caller's version of that closure.
/// Something with no field at all — a selection in a page, which has words to carry and no box to
/// put them in — takes the same control and says what to do with what it heard.
struct SayInto: View {
    let say: Dictation
    /// What to do with the words. Called only when some came back, and awaited, so the capsule is
    /// still saying it is working for as long as the caller is.
    let heard: (String) async -> Void
    /// A glyph in a row's control slot, rather than a word on a line with room for one.
    var compact = false

    /// Into a field: under what it already holds, never over it.
    ///
    /// `gap` is what goes between the two halves — a blank line where the field is prose and the
    /// halves are paragraphs, one space where it is a name or a single word.
    init(say: Dictation, text: Binding<String>, gap: String = " ", compact: Bool = false) {
        self.say = say
        self.compact = compact
        self.heard = { said in
            text.wrappedValue = Underneath.words(said, under: text.wrappedValue, gap: gap)
        }
    }

    /// Somewhere that is not a field. The caller owns what happens to the words, including whether
    /// anything is appended to anything — `Underneath.words` is there to be called if it is.
    init(say: Dictation, compact: Bool = false, heard: @escaping (String) async -> Void) {
        self.say = say
        self.compact = compact
        self.heard = heard
    }

    /// The minimum a finger can be asked to hit. The same raw number `ReviewActions` and
    /// `FilesView` write, and for the same reason: no spacing token means "a finger".
    private static let touch: CGFloat = 44

    var body: some View {
        TalkControl(recorder: say.recorder,
                    mode: say.mode,
                    isMine: true,
                    onStart: {},
                    onClip: { clip in
                        guard let said = await say.words(clip) else { return }
                        await heard(said)
                    },
                    content: { face($0) })
    }

    /// One capsule that fills while it listens. The word and the width stay exactly as they were,
    /// so the control cannot move out from under the finger holding it — the same arrangement
    /// `ReviewActions` uses for Add, and the failure `TalkMark` records having made once already.
    ///
    /// It goes utt orange while it listens and is Deckhand's teal the rest of the time, whatever
    /// the page behind it is doing. Every field in this app is on a sheet, and a sheet keeps the
    /// teal: the page underneath is what turns orange, because that is the screen being recorded
    /// into, and a sheet that changed colour with it would leave nothing to notice.
    private func face(_ state: TalkState) -> some View {
        word
            .font(.system(size: 14))
            .foregroundStyle(state.isRecording || state.busy ? Color.white : Palette.tint)
            .lineLimit(1)
            .padding(.horizontal, compact ? 0 : Spacing.small)
            .frame(minWidth: compact ? Self.touch : 0, minHeight: Self.touch)
            .background(Capsule().fill(fill(state)))
            .contentShape(.capsule)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(spoken(state))
            .accessibilityIdentifier("say-into")
    }

    /// A word where there is room for one, and the glyph alone in a row's control slot — which is
    /// already holding a field and has no width to spare. `ReviewCard`'s attach buttons make the
    /// same two shapes out of the same pair.
    @ViewBuilder private var word: some View {
        if compact {
            Image(systemName: "mic.fill").font(.system(size: 15, weight: .semibold))
        } else {
            Label("Say", systemImage: "mic.fill")
        }
    }

    private func fill(_ state: TalkState) -> Color {
        if state.isRecording { return Palette.recording }
        // Still orange, dimmed: the clip is on the wire and the words are a moment away, which is
        // neither still listening nor nothing happening.
        if state.busy { return Palette.recording.opacity(0.45) }
        return Palette.tileIdle
    }

    /// The whole control is one glyph in a row, so it says what it is and what it will do out
    /// loud — and a spoken label is the one place the hold-or-tap setting can be named.
    private func spoken(_ state: TalkState) -> String {
        if state.busy { return "Transcribing" }
        let what = state.mode == .hold ? "let go" : "tap again"
        if state.isRecording { return "Recording, \(what) to add it to this field" }
        return state.mode == .hold ? "Hold to say this field" : "Tap to say this field"
    }
}
