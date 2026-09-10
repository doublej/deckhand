import Foundation

/// What the mark says while a clip is out, beat by beat.
///
/// The phone cannot watch the round trip happen — the Mac answers once, at the end — so this is a
/// *model* of a round trip rather than a readout of one. The schedule is built on what the trip
/// actually costs, or it would feel wrong: the session lookup is 280–430 ms of shelling out to
/// `it2`, everything else the daemon does itself is under 15 ms combined, and utt is the other
/// 96%, at 1.38 s + 0.068 × the clip's seconds once it is warm.
///
/// Two things follow, and they are the whole design.
///
/// **Nothing here is ever waited on.** The beat is a pure function of how long the wait has
/// already lasted, read by a view that is already drawing — so the instant the Mac answers, the
/// pill drops whatever beat it was on. There is no minimum time a beat is owed and no channel
/// from here to the clip's task; a beat can only ever be overtaken.
///
/// **A long wait is a queue, not a hard clip.** utt serves one job at a time and takes what is
/// already sitting in its folder first, so the same clip has come back at 2.1 s and at 10.1 s
/// minutes apart. The tail beat therefore says *that*, and holds — inventing further stages for a
/// wait that is somebody else's job finishing would be telling the wrong story about the one case
/// where the person most wants to know what is going on.
///
/// The words are `ClipTiming`'s words on purpose: whoever reads `HANDED TO UTT` here and opens
/// the breakdown afterwards should find `Handed to utt` in it and recognise it.
public enum ClipNarration {
    /// One thing the pill says, and the moment it starts saying it.
    public struct Beat: Hashable, Sendable {
        /// Seconds into the wait at which this beat takes the pill over.
        public let after: TimeInterval
        public let word: String

        public init(after: TimeInterval, word: String) {
            self.after = after
            self.word = word
        }
    }

    /// In order, the first at zero.
    ///
    /// The first beat holds for 600 ms, which is longer than a whole round trip that only ever
    /// waited on the Mac's own arithmetic — three words flickering past in a third of a second
    /// reads as a fault rather than as progress, so a short answer shows one word and nothing
    /// else. The three after it are spaced by the same ~600 ms, which is about what a median 2 s
    /// wait can spend per word without turning into a slot machine.
    public static let beats = [
        Beat(after: 0, word: "CLIP ON ITS WAY"),
        Beat(after: 0.6, word: "FINDING SESSION"),
        Beat(after: 1.25, word: "HANDED TO UTT"),
        Beat(after: 2.2, word: "UTT TRANSCRIBING"),
        Beat(after: 3.6, word: "STILL WITH UTT"),
        Beat(after: 5.5, word: "UTT HAS A QUEUE")
    ]

    /// The word for a wait this long. Total by construction — the first beat starts at zero, so
    /// there is always one to show and nothing is ever held back until a beat falls due.
    public static func word(after elapsed: TimeInterval) -> String {
        beats.last { elapsed >= $0.after }?.word ?? beats[0].word
    }

    /// When each beat after the first falls due, for a wait that began at `start`.
    ///
    /// The first is already on screen by then, and the list is finite: once the tail beat is up
    /// there is nothing further to redraw for, which is what stops the pill polling a clock for
    /// the rest of a long queue.
    public static func schedule(from start: Date) -> [Date] {
        beats.dropFirst().map { start.addingTimeInterval($0.after) }
    }
}
