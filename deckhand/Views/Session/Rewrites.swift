import DeckhandKit
import SwiftUI

/// What was changed on the way to this card, who changed it, and a word-level diff of it.
///
/// The card already shows the words that will be sent, and a note saying what the chain swapped.
/// What it could not show is the sentence those words replaced — so a swap that was wrong could
/// be read as a mishearing, and a mishearing as a swap. This is that sentence, laid *over* the
/// one that replaced it rather than under it: a whole before-block asks somebody to read two
/// paragraphs and spot the difference, which is a job a diff does for free.
///
/// **Attribution comes off utt's `stages`, never off comparing `raw` with `text`.** utt hands
/// back `raw` from before *everything*, and one of the stages between them is `hints` — which is
/// this repo's own vocabulary list (`transcribe.VOCABULARY`, `hints_for`), not utt's doing at
/// all. Telling somebody "utt's cleanup rewrote 'deck hand' to 'deckhand'" when the word came
/// out of a list in this codebase would be the UI lying with confidence, which is the worst
/// thing it could do here. Whitespace is not a rewrite either, and `stages` is what utt's own
/// `ProcessedTranscript.changed` uses for that same reason.
///
/// Shut at rest. Nothing appears at all when nothing was rewritten — no empty state, no
/// "unchanged" row.
struct Rewrites: View {
    let filtered: Filtered
    /// The words the chain handed over, which is the far end of both diffs.
    ///
    /// The card draws `words` — what is in the box, corrections and all — and this is
    /// deliberately not that. `Filtered` was built about the *prepared* words (`AppModel.hold`
    /// compares `heard` against them), so an edit typed by hand afterwards belongs to nobody on
    /// this list, and drawing it here would attribute it to a filter that never saw it.
    let prepared: String
    @State private var open = false

    /// Its own type rather than a tuple: `ForEach` wants something identifiable, and who did
    /// the rewriting is already unique among these.
    private struct Change: Identifiable {
        /// Who changed it, which is also the id.
        let id: String
        let before: String
        let after: String
    }

    /// What each of utt's stages is, said so a person knows which app to go and change.
    ///
    /// The three from utt's settings keep utt's own page names, so the disclosure and the page
    /// somebody would go fix use the same words — the same rule the design layer follows.
    /// `hints` is deliberately not phrased as utt's: it is ours.
    private static let whose = [
        "hints": "Deckhand's own word list",
        "replacements": "your word replacements",
        "cleanup": "your transcript cleanup",
        "formatting": "your text formatting",
        "filter": "another utt extension"
    ]

    /// The chain runs utt's raw words → what utt handed over (`heard`) → this Mac's filters →
    /// the prepared words, so there are two diffs in it and each one is somebody else's doing.
    ///
    /// `heard` is nil where the filters changed nothing, and then utt's own far end *is* the
    /// prepared words — which is why it falls back rather than being skipped.
    private var changes: [Change] {
        var found: [Change] = []
        if let raw = filtered.raw, !filtered.uttStages.isEmpty {
            let who = filtered.uttStages.map { Self.whose[$0] ?? $0 }.joined(separator: ", ")
            found.append(Change(id: who, before: raw, after: filtered.heard ?? prepared))
        }
        if let heard = filtered.heard {
            // Both in one name, because both are Deckhand and one diff covers them: the Mac-wide
            // alias list runs before the chain does, so a swap on this line may have come from
            // either. Which one it was is in the note above — this says which app to go and open.
            found.append(Change(id: "this Mac's word list and filters",
                                before: heard, after: prepared))
        }
        return found
    }

    var body: some View {
        if !changes.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Button { open.toggle() } label: { summary }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("what-changed")
                if open {
                    ForEach(changes) { change in swapped(change) }
                }
            }
        }
    }

    /// Named rather than counted, because which one it was is the whole of what a person can act
    /// on: a word list in this repo, a rule in utt's settings, and another extension entirely are
    /// three different places to go.
    private var summary: some View {
        HStack(spacing: Spacing.xxs) {
            Text("Changed by \(changes.map(\.id).joined(separator: ", "))")
                .lineLimit(1)
            Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 8))
            Spacer(minLength: 0)
        }
        .font(Typography.hint)
        .foregroundStyle(Palette.textTertiary)
        .frame(minHeight: 24, alignment: .leading)
        .contentShape(.rect)
    }

    /// One rewrite, in the same face the card draws the words in — the diff and the prompt above
    /// it are meant to be read against each other, and two different faces make that harder.
    private func swapped(_ change: Change) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(change.id.uppercased())
                .font(Typography.eyebrow)
                .tracking(1.0)
                .foregroundStyle(Palette.textTertiary)
            spans(diffWords(from: change.before, to: change.after))
                .font(Typography.mono)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Every span concatenated into one `Text`, so the whole rewrite wraps as the paragraph it
    /// is. A view per word would be a flow layout arguing with the line breaker about something
    /// that is already text.
    private func spans(_ spans: [DiffSpan]) -> Text {
        spans.reduce(Text(verbatim: "")) { line, span in line + drawn(span) }
    }

    /// Three steps of the card's own ink and nothing else: what went is the quietest and struck
    /// through, what stayed sits where a note sits, and what arrived is in the colour the card
    /// draws the prompt itself in — because those words *are* the prompt above.
    private func drawn(_ span: DiffSpan) -> Text {
        switch span {
        case .same(let words):
            Text(verbatim: words).foregroundStyle(Palette.textSecondary)
        case .removed(let words):
            Text(verbatim: words)
                .foregroundStyle(Palette.textTertiary)
                .strikethrough(true, color: Palette.textTertiary)
        case .added(let words):
            Text(verbatim: words).foregroundStyle(Palette.textPrimary)
        }
    }
}
