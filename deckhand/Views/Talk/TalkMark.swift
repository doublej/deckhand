import DeckhandKit
import SwiftUI

/// The mark is the button, and it is the living one: utt's whole show, drifting slowly in
/// Deckhand's teal at rest. While you talk it turns utt orange, speeds up with your voice and
/// dims between words — recording is utt's job in every plugin, so it wears utt's colour. The
/// colour is the screen's (`\.accent`) rather than one this mark picks, because the whole screen
/// wears it: the mark speeding up is what is particular to the mark.
///
/// At rest it is the only thing here: one mark, in the middle, over whatever you were reading.
/// Nothing else — no bar, no label, no ground. Press it and the two things you can do slide out
/// either side, each on its own pill and each centred in its half. They were a row that
/// reflowed whenever the state changed, which moved the button itself, and then a bar behind
/// all three, which put a band of furniture across the page to hold one button.
struct TalkMark: View {
    let state: TalkState
    let level: Double
    /// Whether the words are held for reading before they go. It changes what a tap does, so it
    /// changes what the pill may promise: a tap that opens a review card has not sent anything.
    var confirms = true
    /// The screen's accent, which is already the recording colour by the time this mark is open —
    /// the page it floats over sets it from the same recorder. It used to switch on its own,
    /// which is how the mark went orange on a page that stayed teal around it.
    @Environment(\.accent) private var accent

    /// When the words went out, so the wait can narrate itself. Nil at every other moment,
    /// which is also what takes the narration's clock back down.
    @State private var busySince: Date?

    /// Which of the two word transitions is running, so both can be felt on the phone rather than
    /// argued about from a description. `@AppStorage` and not `Preferences`: that type is a
    /// persisted document with an initialiser, defaults and tests behind it, and this is a design
    /// question with an answer coming — two lines to add and two to delete. See `WordRoll`.
    @AppStorage("talk.letters") private var letters = false

    /// How much room a scrolling pane leaves at the end of its content for the mark to float
    /// over: the mark, its tile, and the air around it.
    static let clearance: CGFloat = 68

    private var isRecording: Bool { state.isRecording }

    var body: some View {
        HStack(spacing: Spacing.extraSmall) {
            said
            mark
            wing(state.canCancel ? "CANCEL" : nil, edge: .trailing, tint: Palette.textSecondary) {
                state.cancel()
            }
        }
        .padding(.vertical, Spacing.extraSmall)
        .animation(Motion.arriving, value: state.canCancel)
        .onChange(of: state.busy) { _, busy in busySince = busy ? .now : nil }
    }

    /// The left-hand pill, redrawn on the beats and on nothing else.
    ///
    /// Only this half is on a timeline: the mark beside it is animating off the microphone and
    /// has no business being re-evaluated because a word changed. The schedule is a fixed list of
    /// instants rather than a tick, so it runs out on its own once the last beat is up — and
    /// `label` is read fresh at each of them, so `busy` going false wins immediately whatever
    /// beat was due next.
    ///
    /// Tappable, not a caption: at rest it says "tap to send", so tapping it sends. The mark does
    /// the same thing, and either is the obvious one to reach for.
    private var said: some View {
        TimelineView(.explicit(due)) { _ in
            let word = label
            wing(word,
                 edge: .leading,
                 tint: isRecording ? accent : Palette.textTertiary,
                 action: state.tapped)
                // Only the pill coming and going. A word replacing another is `WordRoll`'s, and
                // it animates from in there — which is the whole of this fix.
                .animation(Motion.arriving, value: word == nil)
        }
    }

    /// Its own ground and its own shadow, because there is nothing else behind it now — the
    /// page it floats over is whatever you were reading.
    private var mark: some View {
        DotMark.live(
            size: 40,
            tint: accent,
            recording: isRecording,
            level: isRecording ? level : 0,
            hotCore: 0.3
        )
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .fill(Palette.lcdGround)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        )
        .contentShape(.rect)
        // The only thing on this page with no words on it, so it says what it is out loud —
        // and it is what the UI test looks for now that nothing is labelled at rest.
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isRecording ? "Recording, tap to send" : "Talk to this session")
        .accessibilityIdentifier("talk-mark")
    }

    /// One half of the bar: a word on a pill, centred in that half, sliding in from its own
    /// edge. Nothing to say takes the space but draws nothing and catches nothing.
    ///
    /// There is deliberately **no `.id(word)`** here. It was on the pill, so a new word tore the
    /// whole capsule down and built another — invisible while a wait said one word, and the
    /// button flashing six times once the wait learned to narrate itself. The capsule now comes
    /// and goes only when there is something to say or nothing; the word changing inside it is
    /// `WordRoll`'s job. Arriving and leaving are two different animations because they are two
    /// different moments: a thing entering wants a soft landing, a thing leaving wants to be gone.
    @ViewBuilder
    private func wing(_ word: String?,
                      edge: Edge,
                      tint: Color,
                      action: (() -> Void)? = nil) -> some View {
        ZStack {
            if let word {
                pill(word, tint: tint, action: action)
                    .transition(.asymmetric(
                        insertion: .move(edge: edge)
                            .combined(with: .opacity).animation(Motion.arriving),
                        removal: .move(edge: edge)
                            .combined(with: .opacity).animation(Motion.leaving)))
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The capsule, and nothing about the word: what the word is and how it changes is all in
    /// `WordRoll`, including the room around it, because the mask that softens a word sliding out
    /// has to reach the capsule's own edge.
    private func pill(_ word: String, tint: Color, action: (() -> Void)?) -> some View {
        WordRoll(word: word, tint: tint, letters: letters)
            // The mark's own ground, because these slid out from under the mark: three pieces
            // of one control, not two labels visiting from the page they float over.
            .background(
                Capsule(style: .continuous)
                    .fill(Palette.lcdGround)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            )
            // Which makes the ground dark whatever the page is, so the tokens that mean
            // "quieter text" have to resolve against dark or they resolve into it.
            .environment(\.colorScheme, .dark)
            .contentShape(.capsule)
            .onTapGesture { action?() }
            // Split per letter the label is soup, so the whole wing is one element saying the
            // whole word. The hit area is the capsule and never the glyphs — `contentShape` above
            // is what keeps a two-letter word as easy to hit as a sentence.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(word)
            .accessibilityAddTraits(.isButton)
    }

    /// Nothing at rest: the mark says what it is. Only once it is listening is there anything
    /// to tell you, and then there are two things and they are both actions.
    ///
    /// It says what will actually happen. With the review step on, letting go does not send
    /// anything — it transcribes and hands you the words to read — and a button that claims to
    /// send and then does not is worse than one that says nothing.
    ///
    /// Once the clip is out there is nothing left to promise, so the word turns into a story
    /// about where the clip has got to (`ClipNarration`). One sequence for both settings: the
    /// round trip is the same trip either way, and the promise about what happens at the end of
    /// it was already made by the word the person read while their finger was down.
    private var label: String? {
        if state.busy { return ClipNarration.word(after: waited) }
        guard isRecording else { return nil }
        let what = confirms ? "PREVIEW" : "SEND"
        return state.mode == .hold ? "RELEASE TO \(what)" : "TAP TO \(what)"
    }

    /// When each beat falls due. One instant in the far past where nothing is out, because an
    /// explicit schedule wants entries and a list built from `.now` would be a new list every
    /// time this view is read.
    private var due: [Date] {
        guard let busySince else { return [.distantPast] }
        return ClipNarration.schedule(from: busySince)
    }

    /// How long the clip has been out. Zero where nothing saw it leave, which shows the first
    /// beat — the narration degrades to the one word it started as, never to nothing.
    private var waited: TimeInterval {
        guard let busySince else { return 0 }
        return Date.now.timeIntervalSince(busySince)
    }
}
