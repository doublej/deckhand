import Foundation

/// What became of the last clip said to one session, and when the Mac said so.
///
/// A session's page answers "did that go?" twice over — the mark narrates the wait in its own
/// pill, and then the words arrive in the transcript underneath it. The rail and the deck answer
/// it nowhere: there the row *is* the button, and under it is only the next session. This is the
/// sentence a row can say instead, and it is the same sentence the strip at the foot of the rail
/// gets — `AppModel.report` writes both at once.
///
/// It goes stale on purpose. A sentence that stays is furniture, and after a morning's talking
/// six rows would each be carrying one; the clip archive is where the durable record of every
/// send already lives.
public struct Spoken: Equatable, Sendable {
    public let words: String
    /// Not `at`: a two-letter name fails the lint here, and this one has cost time before —
    /// see `.claude/rules/swift-naming.md`. The label stays `at:`, which is what reads at a
    /// call site.
    public let when: Date

    /// How long a row keeps saying it. Long enough to look up from your thumb and read it — a
    /// round trip is seconds and the reading is one glance — and short enough that it is gone
    /// before it becomes part of the row.
    public static let keeps: TimeInterval = 30

    public init(_ words: String, at when: Date = .now) {
        self.words = words
        self.when = when
    }

    /// The words while they are still worth reading, and nothing once they are not.
    ///
    /// Asked rather than expired on a timer: nothing on this phone runs a clock for a sentence,
    /// and both surfaces that draw one are already redrawing every few seconds off their own
    /// listing refresh.
    public func fresh(at now: Date = .now) -> String? {
        now.timeIntervalSince(when) < Self.keeps ? words : nil
    }
}
