import DeckhandKit
import SwiftUI

/// What was changed on the way to this card, and what it said before.
///
/// The card already shows the words that will be sent, and a note saying what the chain swapped.
/// What it could not show is the sentence those words replaced — so a swap that was wrong could
/// be read as a mishearing, and a mishearing as a swap. This is the before.
///
/// Two things can rewrite a spoken prompt and they are told apart, because the answer to each is
/// different. utt's own pipeline runs on the Mac before Deckhand sees anything, and is fixed in
/// utt; Deckhand's chain is this session's own and is edited on its filters page.
///
/// Shut at rest. Nothing here appears at all when nothing was rewritten — no empty state, no
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

    private var changes: [Change] {
        var found: [Change] = []
        if let raw = filtered.raw { found.append(Change(id: "utt's own cleanup", before: raw)) }
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

    private var summary: some View {
        HStack(spacing: Spacing.xxs) {
            Text(changes.count == 1 ? "\(changes[0].id.capitalizedFirst) changed this"
                                    : "utt and the filters both changed this")
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

extension String {
    /// `capitalized` would title-case every word, and "utt" is lowercase on purpose everywhere
    /// in both apps.
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
