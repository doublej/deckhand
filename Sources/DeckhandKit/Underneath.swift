import Foundation

// Where words that were just said go in a field that already has words in it. Here rather than in
// the view for the reason `Fitting` is here: there is nothing visual about it, it is three lines,
// and it is the one place in dictation that can lose somebody's work. Hence a pure function and a
// test.

/// Dictated words joined to whatever the field was already holding.
public enum Underneath {
    /// Under what is there, never instead of it.
    ///
    /// You dictate first and correct second about as often as the other way round, and the one
    /// thing that must not happen is a sentence disappearing because another was said after it.
    /// A field holding nothing gets the new words alone, so nothing ever opens with a stray gap
    /// in front of it, and a clip that came back empty leaves the field exactly as it was.
    ///
    /// The gap is the caller's because only the field knows what two halves of it read as: a
    /// blank line makes two paragraphs out of a spoken transcript, and one space is all a name or
    /// a replacement word can take.
    public static func words(_ said: String, under standing: String, gap: String) -> String {
        let kept = standing.trimmingCharacters(in: .whitespacesAndNewlines)
        let fresh = said.trimmingCharacters(in: .whitespacesAndNewlines)
        if kept.isEmpty { return fresh }
        if fresh.isEmpty { return kept }
        return kept + gap + fresh
    }
}
