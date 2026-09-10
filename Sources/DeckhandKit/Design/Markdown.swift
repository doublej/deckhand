import SwiftUI

/// Text read as a document rather than as its source: a markdown file, and a turn.
///
/// This is a second renderer beside ``Prose``, not a wider one. `Prose` draws exactly the four
/// things a *summary* may contain and shows anything else as the literal characters the model
/// typed — that contract is shared with the daemon's prompt, and widening it would hide a brief
/// that had broken it instead of making it obvious. A `report.md` a session wrote for a person
/// is a different document: `#` and `###` headings, fenced code, numbered and nested lists,
/// sometimes a table. Every one of those through `Prose` lands on screen as punctuation.
///
/// A turn is the same kind of document for a different reason — it has no contract to break, and
/// one session writing to another writes markdown. See `TurnCard.said`.
///
/// Blocks are split by hand here for the same reason they are split there: SwiftUI's own
/// markdown parser is inline-only. It knows `**bold**` and `code` and knows nothing at all
/// about a line that begins `- `, a fence, or a hash.
public struct Markdown: View {
    private let blocks: [Block]
    @Environment(\.diagram) private var diagram

    public init(_ text: String) {
        blocks = Block.parse(text)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                row(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func row(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text): heading(level, text)
        case .bullet(let depth, let text): bullet(depth, text)
        case .numbered(let number, let text): numbered(number, text)
        case .paragraph(let text):
            Text(Inline.styled(text, at: bodySize))
                .font(.system(size: bodySize))
                .foregroundStyle(Palette.textPrimary)
                // Roughly 1.45x the type size, the same ratio a briefing is set at. Text set
                // solid reads as a wall, and a report is opened to be read straight through.
                .lineSpacing(6)
                .padding(.bottom, Spacing.small)
        case .verbatim(let lines):
            Verbatim(lines: lines).padding(.bottom, Spacing.small)
        case .diagram(let lines):
            drawn(lines).padding(.bottom, Spacing.small)
        }
    }

    /// A mermaid block, drawn if this screen knows how and shown as its source if it does not.
    ///
    /// Drawing one needs a web view, and a web view is UIKit — which does not belong in this
    /// module, where everything has to be reachable by `just test` on the Mac with no simulator.
    /// So the app hands the drawing in through the environment and this asks for it. A surface
    /// that never sets one is not broken: it gets the eleven lines of `A-->B`, which is what
    /// every surface got before any of this existed.
    @ViewBuilder private func drawn(_ lines: [String]) -> some View {
        if let draw = diagram {
            draw(lines.joined(separator: "\n"))
        } else {
            Verbatim(lines: lines)
        }
    }

    /// Four sizes and no more, named once here so nothing downstream invents a fifth — and so
    /// inline code can be set to the size of whatever it sits inside. ``Prose`` names its own
    /// for the same reason, and the reason is worth repeating: a fixed mono size cannot be right
    /// in two places at once, and a filename a third larger than the sentence around it is what
    /// makes a page look thrown together.
    private var bodySize: CGFloat { 14 }

    /// Three heading sizes, because a document whose `#` and `###` draw identically has lost the
    /// one thing the formatted view exists for. 20, 17, 14 — the same steps a page title, a
    /// briefing's opening line and body copy already sit on, so the ramp is the app's and not
    /// this file's invention. The third is body size set semibold, which is enough: at that depth
    /// the air above the line is doing most of the work.
    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 20
        case 2: 17
        default: bodySize
        }
    }

    /// The air above a heading is what separates a section from the last, and it is deliberately
    /// much larger than the gaps inside a section. The title of the document needs less of it —
    /// there is nothing above it to be separated from.
    private func heading(_ level: Int, _ text: String) -> some View {
        Text(Inline.styled(text, at: headingSize(level)))
            .font(.system(size: headingSize(level), weight: .semibold))
            .foregroundStyle(Palette.textPrimary)
            .padding(.top, level == 1 ? Spacing.extraSmall : Spacing.large)
            .padding(.bottom, Spacing.extraSmall)
    }

    /// A dot from the same grid the marks are drawn on, not a typographic bullet — the same mark
    /// a briefing's bullets carry, because they are the same thing.
    ///
    /// A child is indented *and* its dot goes quiet. Either alone would do it on a wide page; in
    /// a phone column the indent is only a few points of the line, so the second cue is what
    /// stops a nested list reading as one flat one.
    private func bullet(_ depth: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.extraSmall) {
            Circle()
                .fill(depth == 0 ? Palette.tint : Palette.textTertiary)
                .frame(width: 4, height: 4)
                .offset(y: -1)
            Text(Inline.styled(text, at: bodySize))
                .font(.system(size: bodySize))
                .foregroundStyle(Palette.textPrimary)
                .lineSpacing(5)
        }
        .padding(.leading, CGFloat(depth) * Spacing.medium)
        .padding(.vertical, Spacing.xxs)
    }

    /// The document's own number, never a count of what we have drawn. A list that starts at 3
    /// in the source starts at 3 here: it is the continuation of something further up, and a
    /// silently renumbered step list stops matching whatever it is a list of.
    private func numbered(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.extraSmall) {
            Text(number + ".")
                .font(.system(size: bodySize - 0.5, design: .monospaced))
                .foregroundStyle(Palette.tint)
            Text(Inline.styled(text, at: bodySize))
                .font(.system(size: bodySize))
                .foregroundStyle(Palette.textPrimary)
                .lineSpacing(5)
        }
        .padding(.vertical, Spacing.xxs)
    }

    /// Source kept as source: a fenced code block, and a table — which is the one thing here
    /// deliberately left unrendered, because half a table is harder to read than the pipes.
    ///
    /// Two halves, and both matter. Wrapped, a line of code is unreadable. But one `Text`
    /// holding the whole block unwrapped is how the raw transcript view once drew a blank
    /// screen: past a few thousand points wide CoreText renders *nothing*, with no error and no
    /// warning. So it is one `Text` per line inside a sideways scroll — the long line stays
    /// reachable, and only that one line is ever as wide as itself rather than the whole block.
    /// A single line of several thousand characters is still past that ceiling; nothing a session
    /// writes into a report has one, and if it did only that line would be missing.
    private struct Verbatim: View {
        let lines: [String]

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        // A blank line inside a fence is part of the code; the space keeps its row.
                        Text(line.isEmpty ? " " : line)
                            .font(Typography.mono)
                            .foregroundStyle(Palette.textPrimary)
                    }
                }
                .padding(Spacing.small)
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(Palette.tileIdle)
            )
        }
    }
}

// MARK: - the inline half, shared with Prose

/// Bold and `code` inside a line, in either renderer.
///
/// Lifted out of ``Prose`` rather than copied: it is the one piece the two genuinely have in
/// common, and the rule it carries must not be able to change in one renderer and not the other.
/// That rule is `size` — inline code is set to the size of the text around it, never to a fixed
/// mono size, because the same 12pt filename is too large inside a bullet and too small inside a
/// heading. `Prose`'s four-block contract is the thing that may not be widened, and this is not
/// part of it.
enum Inline {
    /// `tint` is what inline code and any address in the line are drawn in. A parameter rather
    /// than a read of `\.accent`, for the reason ``Links/linked(_:in:)`` gives: this builds an
    /// `AttributedString` outside the view tree, where there is no environment to read. A renderer
    /// that is a view passes what it read — which is how a briefing's code goes utt orange with
    /// the screen around it — and the default keeps everything else on Deckhand's teal.
    static func styled(_ text: String, at size: CGFloat, in tint: Color = Palette.tint) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard var parsed = try? AttributedString(markdown: text, options: options) else {
            return Links.marked(text, in: tint)
        }
        // `AttributedString` marks inline code but does not style it. Half a point under the
        // prose it sits in: a monospaced face at an identical point size still reads as larger.
        for run in parsed.runs where run.inlinePresentationIntent == .code {
            parsed[run.range].font = .system(size: size - 0.5, design: .monospaced)
            parsed[run.range].foregroundColor = tint
        }
        // A session names addresses the way a person would, bare rather than in brackets, so
        // markdown alone leaves the useful half of them dead.
        return Links.linked(parsed, in: tint)
    }
}

// MARK: - which files are offered it

public extension Asset {
    /// Whether the formatted view is offered for this file at all.
    ///
    /// The sheet shows `.txt`, `.json` and `.log` through the same text case, and a document view
    /// means nothing for any of them — so the switch appears for markdown and only markdown.
    /// Both spellings, because a session writes either, and the suffix comes off ``Asset/suffix``
    /// so there is exactly one place in the app that decides what a suffix is.
    var isMarkdown: Bool { suffix == "MD" || suffix == "MARKDOWN" }
}
