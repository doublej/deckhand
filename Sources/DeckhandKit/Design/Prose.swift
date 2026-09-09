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

    public init(_ text: String) {
        blocks = Block.parse(text)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                row(block, lead: index == 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `lead` is the first block, which the brief guarantees is the sentence that stands on
    /// its own. It is set larger than everything under it: one big jump near the top does more
    /// for a page than several small ones spread through it.
    @ViewBuilder private func row(_ block: Block, lead: Bool) -> some View {
        switch block {
        case .heading(let text): heading(text)
        case .bullet(let text): bullet(text)
        case .paragraph(let text):
            Text(inline(text))
                .font(lead ? Typography.lead : Typography.prose)
                .foregroundStyle(lead ? Palette.textPrimary : Palette.textSecondary)
                // Roughly 1.45x the type size. Text set solid reads as a wall; this is the
                // single biggest thing separating a page you read from a page you skim past.
                .lineSpacing(lead ? 7 : 6)
                .padding(.bottom, lead ? Spacing.large : Spacing.medium)
        }
    }

    private func heading(_ text: String) -> some View {
        Text(inline(text))
            .font(Typography.eyebrow)
            .tracking(1)
            .foregroundStyle(Palette.textTertiary)
            .textCase(.uppercase)
            // The air above a heading is what separates one section from the last. It is
            // deliberately much larger than the gap between the lines inside a section —
            // that difference is the only thing telling you where a section begins.
            .padding(.top, Spacing.extraLarge)
            .padding(.bottom, Spacing.small)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.extraSmall) {
            // A dot from the same grid the marks are drawn on, not a typographic bullet.
            Circle()
                .fill(Palette.tint)
                .frame(width: 4, height: 4)
                .offset(y: -1)
            Text(inline(text))
                .font(Typography.prose)
                .foregroundStyle(Palette.textPrimary)
                .lineSpacing(5)
        }
        .padding(.vertical, Spacing.extraSmall)
    }

    /// Bold and code, via SwiftUI's own parser; code additionally gets the mono face, which
    /// `AttributedString` marks but does not style.
    private func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard var parsed = try? AttributedString(markdown: text, options: options) else {
            return Links.marked(text)
        }
        for run in parsed.runs where run.inlinePresentationIntent == .code {
            parsed[run.range].font = Typography.mono
            parsed[run.range].foregroundColor = Palette.tint
        }
        // A summary names addresses the way a person would, bare rather than in brackets, so
        // markdown alone leaves the useful half of them dead.
        return Links.linked(parsed)
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
