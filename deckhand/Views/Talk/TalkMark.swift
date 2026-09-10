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
    /// Whether this mark can reach the clip archive. The one thing about this control that cannot
    /// be worked out by pressing it, so it is the one thing said at rest — see `reach`.
    var clips = false
    /// The screen's accent, which is already the recording colour by the time this mark is open —
    /// the page it floats over sets it from the same recorder. It used to switch on its own,
    /// which is how the mark went orange on a page that stayed teal around it.
    @Environment(\.accent) private var accent

    /// How much room a scrolling pane leaves at the end of its content for the mark to float
    /// over: the mark, its tile, and the air around it.
    static let clearance: CGFloat = 68

    private var isRecording: Bool { state.isRecording }

    var body: some View {
        HStack(spacing: Spacing.extraSmall) {
            // Tappable, not a caption: it says "tap to send", so tapping it sends. The mark
            // does the same thing, and either is the obvious one to reach for.
            wing(label,
                 edge: .leading,
                 tint: isRecording ? accent : Palette.textTertiary,
                 action: state.tapped)
            mark
            wing(state.canCancel ? "CANCEL" : nil, edge: .trailing, tint: Palette.textSecondary) {
                state.cancel()
            }
        }
        .padding(.vertical, Spacing.extraSmall)
        .animation(.snappy(duration: 0.2), value: label)
        .animation(.snappy(duration: 0.2), value: state.canCancel)
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
    @ViewBuilder
    private func wing(_ word: String?,
                      edge: Edge,
                      tint: Color,
                      action: (() -> Void)? = nil) -> some View {
        ZStack {
            if let word {
                pill(word, tint: tint, action: action)
                    .id(word)
                    .transition(.move(edge: edge).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func pill(_ word: String, tint: Color, action: (() -> Void)?) -> some View {
        Text(word)
            .font(Typography.state)
            .tracking(1.4)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, 6)
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
            .accessibilityAddTraits(.isButton)
    }

    /// Nothing at rest: the mark says what it is. Only once it is listening is there anything
    /// to tell you, and then there are two things and they are both actions.
    ///
    /// It says what will actually happen. With the review step on, letting go does not send
    /// anything — it transcribes and hands you the words to read — and a button that claims to
    /// send and then does not is worse than one that says nothing.
    private var label: String? {
        if state.busy { return confirms ? "TRANSCRIBING" : "SENDING" }
        guard isRecording else { return reach }
        let what = confirms ? "PREVIEW" : "SEND"
        return state.mode == .hold ? "RELEASE TO \(what)" : "TAP TO \(what)"
    }

    /// The one sentence at rest, and only where there is somewhere to go.
    ///
    /// Nothing is labelled at rest anywhere else in this app, and that stands: the mark says what
    /// it is by being the mark. This is the exception because the gesture behind it is the press
    /// this mode does *not* use for talking, and that is the only thing here nobody can discover
    /// by trying it. Written as an aside — the dot in front of it — rather than as an instruction,
    /// because the mark is still the button and this is a footnote to it.
    private var reach: String? {
        guard clips else { return nil }
        return state.mode == .hold ? "· TAP FOR CLIPS" : "· HOLD FOR CLIPS"
    }
}
