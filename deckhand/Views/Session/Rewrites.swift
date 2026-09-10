import DeckhandKit
import SwiftUI

/// What was changed on the way to this card, who changed it, and what it said before.
///
/// The card already shows the words that will be sent, and a note saying what the chain swapped.
/// What it could not show is the sentence those words replaced — so a swap that was wrong could
/// be read as a mishearing, and a mishearing as a swap. This is the before.
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
    @State private var open = false

    /// Its own type rather than a tuple: `ForEach` wants something identifiable, and who did
    /// the rewriting is already unique among these.
    private struct Change: Identifiable {
        /// Who changed it, which is also the id.
        let id: String
        let before: String
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

    private var changes: [Change] {
        var found: [Change] = []
        if let raw = filtered.raw, !filtered.uttStages.isEmpty {
            let who = filtered.uttStages.map { Self.whose[$0] ?? $0 }.joined(separator: ", ")
            found.append(Change(id: who, before: raw))
        }
        if let heard = filtered.heard {
            found.append(Change(id: "the filters on this Mac", before: heard))
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
                    ForEach(changes) { change in was(change.before, by: change.id) }
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

    /// The words as they were, in the same face the card draws the words in — the two are meant
    /// to be read against each other, and two different faces make that harder than it is.
    private func was(_ before: String, by who: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("BEFORE \(who.uppercased())")
                .font(Typography.eyebrow)
                .tracking(1.0)
                .foregroundStyle(Palette.textTertiary)
            Text(before)
                .font(Typography.mono)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
