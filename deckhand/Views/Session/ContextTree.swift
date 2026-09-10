import DeckhandKit
import SwiftUI

/// Every CLAUDE.md a session in this folder is loaded with, drawn the way `atlas tree` draws it.
///
/// The other half of the Files tab, and a different question from it: that list is what the
/// session *touched*, bounded by its transcript, and this is what it *started* with. A rule three
/// folders up never appears in a transcript and is shaping every answer all the same.
///
/// The connectors arrive already drawn from the Mac — it knows which branches are still open at
/// every level, and a phone working that out again from a depth number would be a second
/// implementation of one thing. So they are printed in a monospaced font exactly as they were
/// laid out, which is what makes this the same picture the Mac's own tool draws.
///
/// Rows are tighter than the 44pt the file list is careful about, and deliberately: the vertical
/// bars have to nearly meet or the tree stops reading as one, and a row spread to a finger's
/// height breaks the only thing this view is for. The whole row is the target to make up for it.
struct ContextTree: View {
    let context: ContextDocs
    let open: (Asset) -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(context.documents) { row($0) }
                total
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.top, Spacing.extraSmall)
            .padding(.bottom, Spacing.extraLarge)
        }
        .contentMargins(.bottom, TalkMark.clearance, for: .scrollContent)
    }

    private func row(_ doc: Doc) -> some View {
        Button { open(doc.asset) } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.extraSmall) {
                Text(doc.prefix + doc.label)
                    .foregroundStyle(shade(doc.kind))
                    // From the head, so the connector at the front survives and the tail of a
                    // long path — the half that tells two of them apart — survives with it.
                    .truncationMode(.middle)
                if let word = tag(doc.kind) {
                    Text(word).foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: Spacing.extraSmall)
                Text("~\(short(doc.tokens))").foregroundStyle(Palette.textTertiary)
            }
            .font(.system(size: 11, design: .monospaced))
            .lineLimit(1)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("context-row")
        .accessibilityLabel("\(doc.label), \(doc.kind), about \(doc.tokens) tokens")
    }

    /// What the whole tree costs, which is the number the tab is really for: a session in a
    /// folder carrying thirty thousand tokens of instructions starts every conversation with
    /// that much of its window already spent.
    private var total: some View {
        Text("\(context.documents.count) documents · ~\(short(context.tokens)) tokens loaded here")
            .font(Typography.hint)
            .foregroundStyle(Palette.textTertiary)
            .padding(.top, Spacing.medium)
    }

    /// The project is the one you are in, so it is the one set solid. Everything above and
    /// around it is context and is quieter than it.
    private func shade(_ kind: String) -> Color {
        switch kind {
        case "project": accent
        case "ancestor", "root", "descendant": Palette.textPrimary
        default: Palette.textSecondary
        }
    }

    /// Named only where the name is news. `descendant` would appear on most of the rows and says
    /// nothing the shape of the tree has not already said; the rest cannot be worked out by
    /// looking, which is exactly why they earn a word.
    private func tag(_ kind: String) -> String? {
        kind == "descendant" ? nil : kind
    }

    /// atlas's own shorthand: `4.2k` rather than `4259`, because the digits past the first two
    /// are precision an estimate does not have.
    private func short(_ tokens: Int) -> String {
        tokens < 1000 ? "\(tokens)" : String(format: "%.1fk", Double(tokens) / 1000)
    }
}
