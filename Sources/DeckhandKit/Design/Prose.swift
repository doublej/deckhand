import SwiftUI

/// Renders the four things a summary is allowed to contain, and nothing else.
///
/// The daemon's brief and this file are one contract in two places: a heading, a bullet, a
/// paragraph, and inline `code` or **bold** within any of them. Anything the model invents
/// beyond that lands on the screen as the literal characters it typed, which is the honest
/// failure — it looks wrong immediately rather than quietly dropping a sentence.
///
/// Blocks are split here because SwiftUI's own markdown is inline-only: it knows bold and code
/// and knows nothing about a line that begins with `- `.
public struct Prose: View {
    private let blocks: [Block]
    /// Deck size: the same four things in the landscape column's own small type. A briefing set
    /// at reading size in a 240pt column is two paragraphs and no column left.
    private let compact: Bool
    /// A briefing is read inside the session's page and inside a deck column, both of which are
    /// screens you can dictate into, so its bullets and its inline code go orange with them. The
    /// inline half cannot read this itself — see ``Inline/styled(_:at:in:)`` — so it is handed on.
    @Environment(\.accent) private var accent

    public init(_ text: String, compact: Bool = false) {
        blocks = Block.parse(text)
        self.compact = compact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                row(block, lead: index == 0, last: index == blocks.count - 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `lead` is the first block, which the brief guarantees is the sentence that stands on
    /// its own. It is set larger than everything under it: one big jump near the top does more
    /// for a page than several small ones spread through it.
    ///
    /// `last` takes the trailing air off the end. Every block pays for the gap beneath it, which
    /// is right in the middle of a passage and wrong at the end of one: whatever comes after the
    /// prose brings its own space above it, so the two used to add up and the briefing floated
    /// half a section away from what followed it. The rule is that a section's air belongs above
    /// its heading and nowhere else.
    @ViewBuilder private func row(_ block: Block, lead: Bool, last: Bool) -> some View {
        switch block {
        case .heading(let text): heading(text)
        case .bullet(let text): bullet(text)
        case .paragraph(let text):
            Text(Inline.styled(text, at: lead ? leadSize : bodySize, in: accent))
                .font(paragraphFont(lead: lead))
                .foregroundStyle(lead ? Palette.textPrimary : Palette.textSecondary)
                // Roughly 1.45x the type size. Text set solid reads as a wall; this is the
                // single biggest thing separating a page you read from a page you skim past.
                .lineSpacing(compact ? 3 : (lead ? 7 : 6))
                .padding(.bottom, last ? 0 : trailing(lead: lead))
        }
    }

    /// Three sizes and no more, named once here so nothing downstream invents a fourth.
    ///
    /// Every size on the page is one of these or derived from one. It used to be that the body
    /// came from here, inline code came from `Typography.mono` at its own fixed 12pt, and a
    /// heading came from `Typography.eyebrow` at 9 — so a deck column set its prose at 9 and its
    /// code at 12, and every `just check` in a sentence was a third larger than the sentence. In
    /// a full-width briefing the same code was 12 against a 14pt body and came out *smaller*.
    /// The mismatch ran in both directions at once, which is what read as randomness.
    private var bodySize: CGFloat { compact ? 9 : 14 }
    /// The one big jump on the page. It is what makes the first line read first, and it is the
    /// only place a size difference is doing work rather than happening by accident.
    private var leadSize: CGFloat { compact ? 11 : 17 }
    /// Under the body, never level with it: a section marker that competes with the sentences
    /// beneath it stops being a marker.
    private var headingSize: CGFloat { compact ? 8 : 9 }

    private func trailing(lead: Bool) -> CGFloat {
        if compact { return Spacing.extraSmall }
        return lead ? Spacing.large : Spacing.medium
    }

    private func paragraphFont(lead: Bool) -> Font {
        .system(size: lead ? leadSize : bodySize)
    }

    private func heading(_ text: String) -> some View {
        Text(Inline.styled(text, at: headingSize, in: accent))
            .font(.system(size: headingSize, weight: .semibold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(Palette.textTertiary)
            .textCase(.uppercase)
            // The air above a heading is what separates one section from the last. It is
            // deliberately much larger than the gap between the lines inside a section —
            // that difference is the only thing telling you where a section begins.
            .padding(.top, compact ? Spacing.small : Spacing.extraLarge)
            .padding(.bottom, compact ? 2 : Spacing.small)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.extraSmall) {
            // A dot from the same grid the marks are drawn on, not a typographic bullet.
            Circle()
                .fill(accent)
                .frame(width: compact ? 3 : 4, height: compact ? 3 : 4)
                .offset(y: -1)
            Text(Inline.styled(text, at: bodySize, in: accent))
                .font(.system(size: bodySize))
                .foregroundStyle(Palette.textPrimary)
                .lineSpacing(compact ? 2 : 5)
        }
        .padding(.vertical, compact ? 2 : Spacing.extraSmall)
    }

    enum Block: Equatable {
        case heading(String)
        case bullet(String)
        case paragraph(String)

        /// Blank lines separate blocks and carry no meaning of their own, so they are dropped
        /// rather than rendered as space — the blocks bring their own spacing.
        static func parse(_ text: String) -> [Block] {
            text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .compactMap(one)
        }

        private static func one(_ line: String) -> Block? {
            if line.isEmpty { return nil }
            if let heading = line.afterPrefix("## ") { return .heading(heading) }
            if let bullet = line.afterPrefix("- ") { return .bullet(bullet) }
            return .paragraph(line)
        }
    }
}

private extension String {
    func afterPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
