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

@Suite("Turns from a daemon a version behind")
struct TurnDecodingTests {
    @Test("a payload with no tool traces still decodes")
    func olderDaemon() throws {
        // The Mac is updated by a git pull and the phone by a rebuild, so the two are
        // routinely a version apart. A key one of them has not heard of must not cost the
        // whole transcript.
        let json = #"{"role":"assistant","text":"done","timestamp":"t"}"#
        let turn = try JSONDecoder().decode(Turn.self, from: Data(json.utf8))
        #expect(turn.tools.isEmpty)
        #expect(turn.text == "done")
    }

    @Test("and one with them keeps what it was told")
    func newerDaemon() throws {
        let json = """
            {"role":"assistant","text":"done","timestamp":"t",
             "tools":[{"name":"Bash","detail":"just build","succeeded":false}]}
            """
        let turn = try JSONDecoder().decode(Turn.self, from: Data(json.utf8))
        #expect(turn.tools.first?.name == "Bash")
        #expect(turn.tools.first?.succeeded == false)
        #expect(turn.tools.first?.kind == .running)
    }

    @Test("a stamp with fractional seconds reads, which is the one the Mac actually sends")
    func fractional() {
        // Claude Code writes the transcript with milliseconds, and the default
        // `ISO8601DateFormatter` rejects that spelling outright rather than rounding it — so
        // this is the case that decides whether any time is drawn at all.
        let turn = Turn(role: "assistant", text: "done", timestamp: "2026-09-11T13:03:38.974Z")
        #expect(turn.moment?.timeIntervalSince1970 == 1789131818.974)
        #expect(!turn.clock.isEmpty)
    }

    @Test("and one without them reads too")
    func whole() {
        let turn = Turn(role: "assistant", text: "done", timestamp: "2026-09-11T13:03:38Z")
        #expect(turn.moment?.timeIntervalSince1970 == 1789131818)
    }

    @Test("nothing to read draws nothing, rather than a wrong time")
    func unreadable() {
        // Both real: the manager panel builds its turns with no stamp, and a turn still in
        // flight is sent with an empty one because it has not finished happening.
        #expect(Turn(role: "user", text: "hi", timestamp: "").moment == nil)
        #expect(Turn(role: "user", text: "hi", timestamp: "t").moment == nil)
        #expect(Turn(role: "user", text: "hi", timestamp: "t").clock == "")
    }
}

@Suite("What a session asked for and what it made")
struct AskAndAssetTests {
    @Test("a summary from a daemon that does not write task lists still decodes")
    func summaryWithoutTasks() throws {
        let json = #"{"summary":"Done: 14 tests green","headline":"Done: 14 tests green"}"#
        let summary = try JSONDecoder().decode(Summary.self, from: Data(json.utf8))
        #expect(summary.tasks.isEmpty)
        #expect(summary.headline == "Done: 14 tests green")
    }

    @Test("the three states a task can be in survive the wire")
    func taskStates() throws {
        let json = """
            {"summary":"x","tasks":[{"text":"the files tab","state":"doing"},
             {"text":"privacy policy","state":"todo"},{"text":"tray","state":"done"}]}
            """
        let summary = try JSONDecoder().decode(Summary.self, from: Data(json.utf8))
        #expect(summary.tasks.map(\.progress) == [.doing, .todo, .done])
    }

    @Test("a file knows which of the four ways to show it")
    func assetKinds() throws {
        let json = """
            {"files":[{"path":"/tmp/a/shot.png","name":"shot.png","kind":"image",
             "size":120,"modified":1.0},
             {"path":"/tmp/a/take.m4a","name":"take.m4a","kind":"audio",
              "size":900,"modified":2.0}]}
            """
        let body = try JSONDecoder().decode([String: [Asset]].self, from: Data(json.utf8))
        let files = try #require(body["files"])
        #expect(files.map(\.sort) == [.image, .audio])
        #expect(files.first?.folder == "/tmp/a")
    }
}

@Suite("Renaming a session")
struct RenameTests {
    @Test("what you decided about a session follows it to its new name")
    func preferencesFollow() {
        // Keyed by name, because a session that restarts keeps its name and gets a new id.
        // That holds until the name itself changes, and then the star has to be carried.
        var preferences = Preferences(favorites: ["promo"], hidden: ["noisy"])
        preferences.renamed(from: "promo", to: "promo-video-director")
        preferences.renamed(from: "noisy", to: "quiet")

        #expect(preferences.isFavorite("promo-video-director"))
        #expect(!preferences.isFavorite("promo"))
        #expect(preferences.isHidden("quiet"))
        #expect(!preferences.isHidden("noisy"))
    }

    @Test("a session nobody starred stays unstarred under its new name")
    func nothingInvented() {
        var preferences = Preferences()
        preferences.renamed(from: "utt", to: "utt-2")

        #expect(!preferences.isFavorite("utt-2"))
        #expect(!preferences.isHidden("utt-2"))
    }
}
