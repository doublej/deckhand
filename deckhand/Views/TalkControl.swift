import DeckhandKit
import SwiftUI

// A release is not addressable, so the tap it produces is recognised by how close it is to the
// press that caused it: far longer than a release, far shorter than reading back what you just
// said. File scope rather than a static, because `TalkControl` is generic.
// ponytail: a time window; a real one would need the touch identity SwiftUI does not hand out.
private let sameTouch = 0.6

/// The one way to talk to a session. Hold or tap depending on the global setting; the caller
/// decides what it looks like — a bar under a transcript, or a whole column in the deck.
struct TalkControl<Content: View>: View {
    @Bindable var recorder: Recorder
    let mode: TalkMode
    let isMine: Bool
    /// Set where the control is a whole row or column rather than a button of its own. A
    /// surface that big cannot be armed by a tap — the tap already means something there, and
    /// the ones it does not mean are the ones your palm makes.
    var pressToStart = false
    /// What a tap means on a surface that has another job: opening the session it names. Only
    /// while nothing is being recorded — once it is, a tap can only mean "send that".
    var onTap: (() -> Void)?
    let onStart: () -> Void
    let onClip: (URL) async -> Void
    @ViewBuilder let content: (TalkState) -> Content

    @State private var busy = false
    /// When the press that opened the microphone landed. See `tapped`.
    @State private var pressedAt: Date?

    private var isRecording: Bool { recorder.isRecording && isMine }

    var body: some View {
        content(TalkState(isRecording: isRecording,
                          busy: busy,
                          mode: mode,
                          cancel: cancel,
                          stop: stop,
                          tapped: tapped))
            .modifier(TalkGesture(mode: mode,
                                  isRecording: isRecording,
                                  pressToStart: pressToStart,
                                  press: press,
                                  tapped: tapped,
                                  start: start,
                                  stop: stop))
    }

    private func start() {
        guard !recorder.isRecording, !busy else { return }
        onStart()
        Task { _ = await recorder.start() }
    }

    private func press() {
        guard !isRecording else { return }
        pressedAt = .now
        start()
    }

    /// Every meaning a tap can have on this surface, in one place.
    ///
    /// The first of them is "none": a row that is also a button fires on release however long
    /// the finger was down, so the press that opens the microphone is followed instantly by a
    /// tap that would close it again — or, worse, open the page you pressed the row to avoid.
    private func tapped() {
        if let pressedAt, Date.now.timeIntervalSince(pressedAt) < sameTouch { return }
        if isRecording { stop() } else { onTap?() }
    }

    /// Throw the clip away without transcribing it. Holding has its own way out — let go and
    /// say nothing — but a tap-to-talk recording would otherwise have no way back.
    private func cancel() {
        guard isRecording else { return }
        recorder.discard()
    }

    private func stop() {
        guard let clip = recorder.stop() else { return }
        busy = true
        Task {
            await onClip(clip)
            busy = false
        }
    }
}

/// What a talk control is doing, and the one thing its content can ask it to do.
struct TalkState {
    let isRecording: Bool
    let busy: Bool
    let mode: TalkMode
    let cancel: () -> Void
    /// Stop and send.
    let stop: () -> Void
    /// What a tap on this surface means — send, open, or nothing at all. A row that is also a
    /// button has to hand its taps here, because a button wins them before any gesture does.
    let tapped: () -> Void

    /// Only tap-to-talk needs an escape: releasing a hold is already one.
    var canCancel: Bool { isRecording && mode == .toggle }
}

/// Hold means press and release. Tap means one tap to start, another to send — except where
/// the control is a whole row or column, and then a settled press starts it and a tap means
/// whatever `tapped` says it means there.
///
/// On those surfaces it is a plain long press and a plain tap, and that is not fussiness. A
/// high-priority or exclusive gesture takes the touch away from the row, and a row in a list
/// has two other jobs living on that same touch: opening the session, and swiping it to star.
/// Taking the touch broke both, and the row cannot be a `Button` either — a button wins the
/// touch the other way and the press never arrives. The UI test holds all three down.
private struct TalkGesture: ViewModifier {
    let mode: TalkMode
    let isRecording: Bool
    let pressToStart: Bool
    let press: () -> Void
    let tapped: () -> Void
    let start: () -> Void
    let stop: () -> Void

    /// A press has to settle before it counts as talking. Without the wait, a finger dragged
    /// across the deck to scroll it starts recording instead of scrolling.
    private static let settle = 0.2

    @ViewBuilder func body(content: Content) -> some View {
        switch mode {
        case .hold where pressToStart:
            // Hold means let go to send, and `onPressingChanged` is where letting go is known
            // without a drag gesture in it — a drag is what a list reads as a swipe.
            content
                .onLongPressGesture(minimumDuration: Self.settle, perform: press) { down in
                    if !down { stop() }
                }
                .onTapGesture { tapped() }
        case .hold:
            content.gesture(held)
        case .toggle where pressToStart:
            content
                .onLongPressGesture(minimumDuration: Self.settle) { press() }
                .onTapGesture { tapped() }
        case .toggle:
            content.onTapGesture { isRecording ? stop() : start() }
        }
    }

    private var held: some Gesture {
        LongPressGesture(minimumDuration: Self.settle)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, _) = value, !isRecording { press() }
            }
            .onEnded { _ in stop() }
    }

    private var pressed: some Gesture {
        LongPressGesture(minimumDuration: Self.settle)
            .onEnded { _ in press() }
    }
}

/// The mark is the button, and it is the living one: utt's whole show, drifting slowly in
/// Deckhand's teal at rest. While you talk it turns utt orange, speeds up with your voice and
/// dims between words — recording is utt's job in every plugin, so it wears utt's colour.
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
                 tint: isRecording ? Palette.recording : Palette.textTertiary,
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
            tint: isRecording ? Palette.recording : Palette.tint,
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
        guard isRecording else { return nil }
        let what = confirms ? "PREVIEW" : "SEND"
        return state.mode == .hold ? "RELEASE TO \(what)" : "TAP TO \(what)"
    }
}
