import DeckhandKit
import SwiftUI

/// The word a talk control is saying right now, redrawn on the narration's own beats and on
/// nothing else.
///
/// It lived inside `TalkMark`'s left-hand pill until the rail and the deck wanted the same words.
/// One copy of the words and one copy of the schedule, or the three surfaces drift — and drifting
/// here means one screen promising SEND where another promises PREVIEW for the very same press.
///
/// It hands the word out rather than drawing it, because only this view is on a timeline: the
/// mark beside the pill has no business being re-evaluated because a word changed.
struct TalkNarration<Content: View>: View {
    let state: TalkState
    /// Whether the words are held for reading before they go. It changes what a release does, so
    /// it changes what may be promised: a release that opens a review card has not sent anything.
    var confirms = true
    @ViewBuilder let content: (String?) -> Content

    /// When the words went out, so the wait can narrate itself. Nil at every other moment,
    /// which is also what takes the narration's clock back down.
    @State private var busySince: Date?

    var body: some View {
        // The schedule is a fixed list of instants rather than a tick, so it runs out on its own
        // once the last beat is up — and `word` is read fresh at each of them, so `busy` going
        // false wins immediately whatever beat was due next.
        TimelineView(.explicit(due)) { _ in content(word) }
            .onChange(of: state.busy) { _, busy in busySince = busy ? .now : nil }
    }

    /// Nothing at rest: a mark says what it is and a row says whose it is. Only once it is
    /// listening is there anything to tell you, and then there are two things and they are both
    /// actions.
    ///
    /// It says what will actually happen. With the review step on, letting go does not send
    /// anything — it transcribes and hands you the words to read — and a button that claims to
    /// send and then does not is worse than one that says nothing.
    ///
    /// Once the clip is out there is nothing left to promise, so the word turns into a story
    /// about where the clip has got to (`ClipNarration`). One sequence for both settings: the
    /// round trip is the same trip either way, and the promise about what happens at the end of
    /// it was already made by the word the person read while their finger was down.
    private var word: String? {
        if state.busy { return ClipNarration.word(after: waited) }
        guard state.isRecording else { return nil }
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

/// One line for a surface with no mark and no transcript: what the clip is doing, and then what
/// became of it.
///
/// The rail and the deck record from the row itself, so everything a session's page says about a
/// clip happens somewhere those screens cannot see — the narration is in a mark they do not have,
/// and the words land in a transcript they are not showing. Held a row down, let go, and nothing
/// on the rail ever said whether the session got it. This is that answer, on the row it was said
/// to.
///
/// The words in flight are the mark's own, through `TalkNarration`. The sentence afterwards is the
/// one on the strip at the foot of the rail: `AppModel.report` writes both at once, so a row can
/// never be told something the strip was not, and it goes quiet on its own — see `Spoken`.
struct TalkLine: View {
    let state: TalkState
    var confirms = true
    /// What became of the last clip said here, once there is nothing in flight to narrate. Nil
    /// while a review card is up: the card is already saying where the words are going and what
    /// will be done to them, and a line repeating it is the app saying it twice on one row.
    var spoken: String?
    /// A deck column, which is 240 points wide and writes everything at the deck's own size.
    var compact = false
    @Environment(\.accent) private var accent

    /// Whether there is anything at all to draw.
    ///
    /// Asked by the surfaces rather than answered by an empty body, because a zero-height view is
    /// still a child: a stack would keep spacing either side of it and every quiet row on the
    /// rail would pay a gap for the one that is talking.
    static func speaks(_ state: TalkState, spoken: String?) -> Bool {
        state.isRecording || state.busy || spoken != nil
    }

    var body: some View {
        TalkNarration(state: state, confirms: confirms) { word in
            Group {
                if let word {
                    // A state, so it is written the way every other state on this rail is:
                    // tracked mono in the colour the screen is already wearing, which is utt
                    // orange for exactly as long as the microphone is open.
                    line(word, in: accent, font: compact ? Self.deck : Typography.state)
                        .tracking(1)
                } else if let spoken {
                    // A sentence rather than a state word, so it is set as one and held back: it
                    // is a receipt, and the row under it is what you came to the rail to read.
                    line(spoken, in: Palette.textTertiary,
                         font: compact ? Self.deck : Typography.hint)
                }
            }
            .animation(Motion.word, value: word)
        }
    }

    /// The deck's own size. Every word in a column is eight or nine points; a line borrowing the
    /// rail's eleven would be the largest type on the screen.
    private static let deck = Font.system(size: 8, weight: .semibold, design: .monospaced)

    private func line(_ words: String, in colour: Color, font: Font) -> some View {
        Text(words)
            .font(font)
            .foregroundStyle(colour)
            // Two, not one: a refusal names the filter and says why, and truncating that to an
            // ellipsis loses the half a person can act on. Short lines still take one.
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(words)
    }
}
