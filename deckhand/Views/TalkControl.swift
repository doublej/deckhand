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
    /// The press that is not talking, or nil where there is no room for a second gesture on this
    /// touch. What it opens is the caller's business — it went straight to the clip archive and
    /// now offers three things — so this control knows only that there is a second press to give.
    var onReach: (() -> Void)?
    let onStart: () -> Void
    let onClip: (URL) async -> Void
    @ViewBuilder let content: (TalkState) -> Content

    @State private var busy = false
    /// When this control last answered a press — the one that opened the microphone, the one that
    /// closed it, or the other gesture entirely. See `claimed`.
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
                                  pressToStart: pressToStart,
                                  press: press,
                                  tapped: tapped,
                                  toggled: toggled,
                                  reach: reaching,
                                  claim: claim,
                                  stop: stop))
    }

    /// Nil where nothing installs a second gesture at all, which is every surface that already
    /// spends this touch on something else. Written out rather than as a ternary because the
    /// two branches are a method reference and `nil`, and inference does badly with that pair.
    private var reaching: (() -> Void)? {
        guard onReach != nil else { return nil }
        return reach
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
    ///
    /// A surface with no other job for a tap gets the second press's menu instead, which is what
    /// makes the left-hand pill work: it is a tap like any other and it means whatever a tap
    /// means here.
    private func tapped() {
        guard claimed() else { return }
        if isRecording { stop() } else if let onTap { onTap() } else { onReach?() }
    }

    /// A tap where tapping is how you talk.
    ///
    /// It goes through the same claim as everything else because of the long press beside it: one
    /// physical press reaches both gestures, and the tap its release makes must not start a
    /// recording the instant that menu has opened.
    private func toggled() {
        guard claimed() else { return }
        if isRecording { stop() } else { start() }
    }

    /// The press this mode does not use for talking. Never while recording — what it opens is
    /// something to read or pick from, and reaching it mid-clip would leave the microphone open
    /// behind it, which is also why nothing about the mark may change size while it is down.
    private func reach() {
        guard !isRecording, claimed() else { return }
        onReach?()
    }

    /// Claim this touch outright, so whatever it produces next is ignored. Used when a long
    /// press has opened the second gesture's menu: its release still arrives as a tap, and in
    /// tap-to-talk a tap starts recording — so without this, reaching for a picture would open
    /// the microphone behind the menu.
    private func claim() { pressedAt = .now }

    /// True when this touch has not already been answered, and claims it when it has not.
    ///
    /// Two gestures now live on one control and a single press can reach both of them: a release
    /// arrives as a tap a moment later, and a tap is one of the two. A release is not addressable,
    /// so the only thing telling them apart is how close together they are.
    private func claimed() -> Bool {
        if let pressedAt, Date.now.timeIntervalSince(pressedAt) < sameTouch { return false }
        pressedAt = .now
        return true
    }

    /// Throw the clip away without transcribing it. Holding has its own way out — let go and
    /// say nothing — but a tap-to-talk recording would otherwise have no way back.
    private func cancel() {
        guard isRecording else { return }
        recorder.discard()
    }

    private func stop() {
        guard let clip = recorder.stop() else { return }
        // Letting go of a hold arrives as a tap a moment later, and on a control that can reach
        // that menu a tap is the gesture that opens it. Claiming the touch here is what stops a
        // clip being sent and the menu opening over the top of it on the same press.
        pressedAt = .now
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
    let pressToStart: Bool
    let press: () -> Void
    let tapped: () -> Void
    let toggled: () -> Void
    /// The press that is not talking, where this surface has one. Installed here rather than in
    /// a modifier of its own, and that is the entire fix for tap-to-talk: as a second modifier it
    /// wrapped this one, so its long press sat *outside* the tap and took the touch before the
    /// tap could have it. Every working pair in this file is long press inner, tap outer.
    let reach: (() -> Void)?
    /// Take the touch, so the tap a long press ends with cannot also be acted on.
    let claim: () -> Void
    let stop: () -> Void

    /// Longer than the settle a recording needs, because in tap-to-talk the two are in a race
    /// and the recording is the one a slow finger means far more often.
    private static let longer = 0.45

    /// A press has to settle before it counts as talking. Without the wait, a finger dragged
    /// across the deck to scroll it starts recording instead of scrolling.
    private static let settle = 0.2

    @ViewBuilder func body(content: Content) -> some View {
        switch mode {
        case .hold:
            // Hold means let go to send, and `onPressingChanged` is where letting go is known
            // without a drag gesture in it — a drag is what a list reads as a swipe.
            //
            // One case for both surfaces now, and that is a bug fix rather than tidying. The
            // floating mark used to take `.gesture(held)` — a long press *sequenced before* a
            // zero-distance drag — with the tap outside it, and that pairing does not work: the
            // sequence claims the touch on the way down, so the tap never arrived and the press
            // this mode leaves spare reached nothing. Hold-to-talk is the default, so in the
            // default mode the clip archive was unreachable from a session's page, and the menu
            // that replaced it with it. `.onLongPressGesture` + `.onTapGesture` is the pairing
            // that does work — it is what a list row has always used for the very same job, and
            // what tap-to-talk's own reach uses. A UI test holds the difference down.
            content
                .onLongPressGesture(minimumDuration: Self.settle, perform: press) { down in
                    if !down { stop() }
                }
                // `tapped()` and not `reach?() ?? tapped()`: it already routes to the reach when
                // there is no other job for a tap here, and unlike `reach` it answers a tap made
                // *while recording* by sending — which is what the mark's own accessibility label
                // has been promising all along.
                .onTapGesture { tapped() }
        case .toggle where pressToStart:
            content
                .onLongPressGesture(minimumDuration: Self.settle) { press() }
                .onTapGesture { tapped() }
        case .toggle where reach != nil:
            reaching(content)
        case .toggle:
            content.onTapGesture { toggled() }
        }
    }

    /// Both gestures, in this order. The long press opens the other three things; the tap talks.
    /// Its release arrives as a tap a moment later, so the claim on letting go is what stops the
    /// menu opening and the microphone opening on the same press.
    private func reaching(_ content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: Self.longer) { down in
                if !down { claim() }
            } perform: {
                reach?()
            }
            .onTapGesture { toggled() }
    }

}
