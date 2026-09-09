import DeckhandKit
import SwiftUI

/// The one way to talk to a session. Hold or tap depending on the global setting; the caller
/// decides what it looks like — a bar under a transcript, or a whole column in the deck.
struct TalkControl<Content: View>: View {
    @Bindable var recorder: Recorder
    let mode: TalkMode
    let isMine: Bool
    let onStart: () -> Void
    let onClip: (URL) async -> Void
    @ViewBuilder let content: (TalkState) -> Content

    @State private var busy = false

    private var isRecording: Bool { recorder.isRecording && isMine }

    var body: some View {
        content(TalkState(isRecording: isRecording, busy: busy, mode: mode, cancel: cancel))
            .contentShape(.rect)
            .modifier(TalkGesture(mode: mode, isRecording: isRecording, start: start, stop: stop))
    }

    private func start() {
        guard !recorder.isRecording, !busy else { return }
        onStart()
        Task { _ = await recorder.start() }
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

    /// Only tap-to-talk needs an escape: releasing a hold is already one.
    var canCancel: Bool { isRecording && mode == .toggle }
}

/// Hold means press and release. Tap means one tap to start, another to send.
private struct TalkGesture: ViewModifier {
    let mode: TalkMode
    let isRecording: Bool
    let start: () -> Void
    let stop: () -> Void

    /// A press has to settle before it counts as talking. Without the wait, a finger dragged
    /// across the deck to scroll it starts recording instead of scrolling.
    private static let settle = 0.2

    func body(content: Content) -> some View {
        switch mode {
        case .hold:
            content.gesture(
                LongPressGesture(minimumDuration: Self.settle)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        if case .second(true, _) = value, !isRecording { start() }
                    }
                    .onEnded { _ in stop() }
            )
        case .toggle:
            content.onTapGesture { isRecording ? stop() : start() }
        }
    }
}

/// The mark is the button, and it is the living one: utt's whole show, drifting slowly in
/// Deckhand's teal at rest. While you talk it turns utt orange, speeds up with your voice and
/// dims between words — recording is utt's job in every plugin, so it wears utt's colour.
/// The label says exactly what a press will do.
struct TalkMark: View {
    let state: TalkState
    let level: Double

    private var isRecording: Bool { state.isRecording }

    var body: some View {
        VStack(spacing: Spacing.extraSmall) {
            DotMark.live(
                size: 72,
                tint: isRecording ? Palette.recording : Palette.tint,
                recording: isRecording,
                level: isRecording ? level : 0,
                hotCore: 0.3
            )
            .padding(Spacing.extraSmall)
            .background(
                RoundedRectangle(cornerRadius: Radius.extraLarge, style: .continuous)
                    .fill(Palette.lcdGround)
            )
            HStack(spacing: Spacing.small) {
                Text(label)
                    .font(Typography.pill)
                    .tracking(1.4)
                    .foregroundStyle(isRecording ? Palette.recording : Palette.textTertiary)
                if state.canCancel {
                    Button("CANCEL", action: state.cancel)
                        .buttonStyle(.plain)
                        .font(Typography.pill)
                        .tracking(1.4)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.medium)
        .contentShape(.rect)
    }

    private var label: String {
        if state.busy { return "SENDING" }
        if isRecording { return state.mode == .hold ? "RELEASE TO SEND" : "TAP TO SEND" }
        return state.mode == .hold ? "HOLD TO TALK" : "TAP TO TALK"
    }
}
