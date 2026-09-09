import Foundation
import Testing

@testable import DeckhandKit

@Suite("Summary markup")
struct ProseTests {
    /// A real answer from the summariser, so the test fails if the daemon's brief and this
    /// parser ever stop describing the same four things.
    let real = """
        Debugged a promo video build script (`cut1-promo2.sh`) and got the preview rendering.

        ## Fixes applied
        - Swapped `printf` rounding for `bc` after a locale mismatch
        - Added a trailing newline, since `read` was failing under `set -e`

        **Still open**: confirming the recording composites onto the canvas.
        """

    @Test("the four blocks are told apart")
    func blocks() {
        let parsed = Prose.Block.parse(real)
        #expect(parsed.count == 5)
        #expect(parsed[0] == .paragraph(
            "Debugged a promo video build script (`cut1-promo2.sh`) and got the preview rendering."
        ))
        #expect(parsed[1] == .heading("Fixes applied"))
        #expect(parsed[2] == .bullet("Swapped `printf` rounding for `bc` after a locale mismatch"))
        #expect(parsed[4] == .paragraph(
            "**Still open**: confirming the recording composites onto the canvas."
        ))
    }

    @Test("blank lines carry no meaning of their own")
    func blanks() {
        #expect(Prose.Block.parse("one\n\n\n\ntwo") == [.paragraph("one"), .paragraph("two")])
        #expect(Prose.Block.parse("   \n \n").isEmpty)
    }

    @Test("a marker only counts with its space, so prose is never mistaken for markup")
    func markers() {
        // "-5 degrees" is a sentence, not a bullet; "##2" is not a heading.
        #expect(Prose.Block.parse("-5 degrees colder") == [.paragraph("-5 degrees colder")])
        #expect(Prose.Block.parse("##2 failed") == [.paragraph("##2 failed")])
        #expect(Prose.Block.parse("- ") == [.paragraph("-")])
    }

    @Test("anything the model invents beyond the four stays visible as itself")
    func unsupported() {
        // A table row is not silently dropped: it lands as a paragraph, which looks wrong on
        // screen straight away rather than quietly losing a line.
        let odd = "| a | b |\n> quoted\n1. numbered"
        #expect(Prose.Block.parse(odd) == [
            .paragraph("| a | b |"), .paragraph("> quoted"), .paragraph("1. numbered")
        ])
    }
}

@Suite("Comparing what was said with what came back")
struct CollapsedTests {
    @Test("whitespace is flattened, because the daemon flattens it on the way out")
    func flattens() {
        #expect("run   the\n\ttests".collapsed == "run the tests")
        #expect("  leading and trailing  ".collapsed == "leading and trailing")
    }

    @Test("an attributed copy still contains what was said")
    func attribution() {
        // The socket route prefixes the words, so the turn that comes back is never equal to
        // what was shown -- only ever a superstring of it once both are collapsed.
        let said = "run the tests\nand report back"
        let came = "JJ, spoken: run  the tests and report back"
        #expect(came.collapsed.contains(said.collapsed))
    }
}
