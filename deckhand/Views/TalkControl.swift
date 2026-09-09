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
            .contentShape(.rect)
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
/// The mark sits in the middle and the two things you can do slide out either side of it: what
/// a tap will do from the left, the way out from the right, each centred in its own half. They
/// were a row that reflowed every time the state changed, which moved the button itself — the
/// one thing on the page that must not move while your thumb is coming down on it.
struct TalkMark: View {
    let state: TalkState
    let level: Double

    /// How much room a scrolling pane leaves at the end of its content for this to float over.
    /// The mark is 40, plus its tile, plus the capsule around it.
    static let clearance: CGFloat = 76

    private var isRecording: Bool { state.isRecording }

    var body: some View {
        HStack(spacing: Spacing.extraSmall) {
            wing(label, edge: .leading, tint: isRecording ? Palette.recording : Palette.textTertiary)
            mark
            wing(state.canCancel ? "CANCEL" : nil, edge: .trailing, tint: Palette.textSecondary) {
                state.cancel()
            }
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.extraSmall)
        .background(
            Capsule(style: .continuous)
                .fill(Palette.surfacePrimary)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        )
        .overlay(Capsule(style: .continuous).strokeBorder(Palette.strokeHairline))
        .animation(.snappy(duration: 0.2), value: label)
        .animation(.snappy(duration: 0.2), value: state.canCancel)
        .contentShape(.capsule)
    }

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
        )
    }

    /// One half of the bar: a word centred in it, sliding in from its own edge. Nothing to say
    /// still takes the space, so the mark stays where it was.
    @ViewBuilder
    private func wing(_ word: String?,
                      edge: Edge,
                      tint: Color,
                      action: (() -> Void)? = nil) -> some View {
        ZStack {
            if let word {
                Text(word)
                    .font(Typography.pill)
                    .tracking(1.4)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .id(word)
                    .transition(.move(edge: edge).combined(with: .opacity))
                    .onTapGesture { action?() }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var label: String? {
        if state.busy { return "SENDING" }
        if isRecording { return state.mode == .hold ? "RELEASE TO SEND" : "TAP TO SEND" }
        return state.mode == .hold ? "HOLD TO TALK" : "TAP TO TALK"
    }
}
