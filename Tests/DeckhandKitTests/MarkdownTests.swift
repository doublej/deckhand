import Foundation
import Testing

@testable import DeckhandKit

@Suite("A markdown file read as a document")
struct MarkdownTests {
    /// A report in the shape a session actually writes one, carrying every block kind the
    /// renderer claims to handle — including the two traps: a `#` and a `- ` inside a fence,
    /// and an ordered list that does not start at 1.
    let report: String = {
        let url = Bundle.module.url(forResource: "Fixtures/report", withExtension: "md")
        return (try? String(contentsOf: url!, encoding: .utf8)) ?? ""
    }()

    /// One tag per block, so the shape of the whole document is a single expectation: which
    /// heading level, which nesting depth, which number the list kept.
    private func shape(_ blocks: [Markdown.Block]) -> [String] {
        blocks.map { block in
            switch block {
            case .heading(let level, _): "h\(level)"
            case .bullet(let depth, _): "b\(depth)"
            case .numbered(let number, _): "n\(number)"
            case .paragraph: "p"
            case .verbatim: "v"
            case .diagram: "d"
            }
        }
    }

    @Test("every block a real report contains is told apart")
    func blocks() {
        let parsed = Markdown.Block.parse(report)
        #expect(shape(parsed) == [
            "h1", "p", "h2", "b0", "b0", "b1", "b0", "h3", "n3", "n4", "v", "v", "h3", "p"
        ])
        #expect(parsed[0] == .heading(1, "Promo video build"))
        #expect(parsed[3] == .bullet(0, "Swapped `printf` rounding for `bc`"))
        // `* ` is a bullet as much as `- ` is, and it sits in the same list.
        #expect(parsed[6] == .bullet(0, "Pinned ffmpeg to the Entware build"))
        #expect(parsed[13] == .paragraph("Confirming the recording composites onto the canvas."))
    }

    @Test("everything inside a fence is literal, hashes and dashes included")
    func fenced() {
        let parsed = Markdown.Block.parse(report)
        #expect(parsed[10] == .verbatim([
            "# not a heading",
            "for clip in *.mov; do",
            "  - not a bullet",
            #"  ffmpeg -i "$clip" -vf scale=1280:-2 "out/$clip""#,
            "done"
        ]))
        // The proof is in what did *not* happen: nothing in the document became a heading
        // called "not a heading" or a bullet called "not a bullet".
        #expect(!parsed.contains(.heading(1, "not a heading")))
        #expect(!parsed.contains(.bullet(1, "not a bullet")))
        // Indentation inside a fence is code, so the lines are kept unstripped.
        #expect(parsed[10] != .verbatim(["# not a heading"]))
    }

    @Test("an ordered list keeps the document's own numbers")
    func numbers() {
        let parsed = Markdown.Block.parse(report)
        // Starting at 3 because it continues something above it. Renumbering from 1 here is
        // how a list of steps stops matching the thing it is a list of.
        #expect(parsed[8] == .numbered("3", "Re-render the preview"))
        #expect(parsed[9] == .numbered("4", "Check the composite against the canvas"))
    }

    @Test("a table stays raw rather than half-rendered")
    func table() {
        let parsed = Markdown.Block.parse(report)
        #expect(parsed[11] == .verbatim(["| stage | seconds |", "| --- | --- |", "| render | 41 |"]))
    }

    @Test("heading depth survives, and anything deeper than three shares the third")
    func depths() {
        #expect(Markdown.Block.parse("# one\n## two\n### three") == [
            .heading(1, "one"), .heading(2, "two"), .heading(3, "three")
        ])
        // A fourth hash is not a fourth size; it is the smallest heading, not four characters
        // of punctuation in the middle of a page.
        #expect(Markdown.Block.parse("#### four") == [.heading(3, "four")])
        #expect(Markdown.Block.parse("####### seven") == [.paragraph("####### seven")])
    }

    @Test("a marker only counts with its space, so prose is never mistaken for markup")
    func markers() {
        #expect(Markdown.Block.parse("#hashtag") == [.paragraph("#hashtag")])
        #expect(Markdown.Block.parse("-5 degrees colder") == [.paragraph("-5 degrees colder")])
        #expect(Markdown.Block.parse("1.no space") == [.paragraph("1.no space")])
        #expect(Markdown.Block.parse("2026 was the year") == [.paragraph("2026 was the year")])
    }

    @Test("an unterminated fence is still the code it was")
    func unterminated() {
        // Dropping it would lose the rest of a document over one missing line of backticks.
        #expect(Markdown.Block.parse("```\nswift build\n") == [.verbatim(["swift build"])])
        // And a stray pair draws nothing rather than an empty box.
        #expect(Markdown.Block.parse("```\n```").isEmpty)
    }

    @Test("the switch is offered for markdown and for nothing else")
    func offered() {
        // Off `Asset.suffix`, so there is one place in the app that decides what a suffix is.
        #expect(asset("report.md").isMarkdown)
        #expect(asset("NOTES.MARKDOWN").isMarkdown)
        #expect(!asset("transcript.txt").isMarkdown)
        #expect(!asset("report.md.bak").isMarkdown)
        #expect(!asset("Justfile").isMarkdown)
    }

    private func asset(_ name: String) -> Asset {
        Asset(path: "/tmp/\(name)", name: name, kind: "text", size: 10, modified: 1)
    }

    /// The case a transcript adds to the ones a report already had.
    ///
    /// A turn is drawn through this renderer now, and the turns in this repo are full of sessions
    /// showing each other the machine tags the daemon strips. Inside a fence they are code — the
    /// walk must not read the hash, the dash or the tag, and must hand every line back whole.
    @Test("a fence holding the tags the daemon strips is code, line for line")
    func quotedTagsSurvive() {
        let quoted = [
            #"<teammate-message teammate_id="mate" summary="y">"#,
            "# not a heading",
            "- not a bullet",
            "</teammate-message>"
        ]
        let fence = ["What comes off:", "", "```"] + quoted
            + ["```", "", "and `<system-reminder>` inline."]

        #expect(Markdown.Block.parse(fence.joined(separator: "\n")) == [
            .paragraph("What comes off:"),
            .verbatim(quoted),
            .paragraph("and `<system-reminder>` inline.")
        ])
    }

    /// What one session writes to another, in the shape the daemon hands it over: the label it
    /// gained where its envelope was, and the markdown it was always written in.
    @Test("a peer's message is a document, not a line of punctuation")
    func peerTurn() {
        let blocks = Markdown.Block.parse("""
        **From the mate:** main fast-forwarded

        ## What landed

        - `just check` exit 0
        1. nothing pushed
        """)

        #expect(shape(blocks) == ["p", "h2", "b0", "n1"])
        #expect(blocks[0] == .paragraph("**From the mate:** main fast-forwarded"))
        #expect(blocks[2] == .bullet(0, "`just check` exit 0"))
    }
}

/// The one fence whose contents are not the answer.
@Suite("Diagrams")
struct DiagramTests {
    @Test("a mermaid fence is a diagram and every other fence is still code")
    func tellsThemApart() {
        let blocks = Markdown.Block.parse("""
        Before.

        ```mermaid
        graph TD
          A[Phone] --> B[Mac]
        ```

        ```swift
        let x = 1
        ```

        ```
        plain
        ```
        """)
        #expect(blocks.contains(.diagram(["graph TD", "  A[Phone] --> B[Mac]"])))
        #expect(blocks.contains(.verbatim(["let x = 1"])))
        #expect(blocks.contains(.verbatim(["plain"])))
        #expect(blocks.first == .paragraph("Before."))
    }

    /// The language is the word after the backticks and nothing else on the line, so a fence with
    /// a title on it is still the diagram it says it is. Case is not a promise anybody makes.
    @Test("the rest of the info string is nobody's business")
    func readsTheLanguage() {
        #expect(Markdown.Block.parse("```Mermaid\nflowchart LR\n```") == [.diagram(["flowchart LR"])])
        #expect(Markdown.Block.parse("```mermaid title=Flow\nflowchart LR\n```")
                == [.diagram(["flowchart LR"])])
        // Not mermaid, and not almost-mermaid either.
        #expect(Markdown.Block.parse("```mermaidish\nx\n```") == [.verbatim(["x"])])
    }

    /// Two fences in a row, where the second must not inherit the first one's language — the bug
    /// this shape makes impossible, and the reason the word is cleared on close.
    @Test("a language does not leak into the next fence")
    func forgetsBetweenFences() {
        let blocks = Markdown.Block.parse("```mermaid\ngraph TD\n```\n```\nnot a diagram\n```")
        #expect(blocks == [.diagram(["graph TD"]), .verbatim(["not a diagram"])])
    }
}
