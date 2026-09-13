import Foundation
import Testing

@testable import DeckhandKit

@Suite("What a dashboard tile says")
struct DashboardTests {
    @Test("two squares across a phone held upright, four on its side")
    func columns() {
        // The widths are real ones: an SE, a 12 Pro upright, the same phone on its side, an iPad.
        #expect(Dashboard.columns(across: 320) == 2)
        #expect(Dashboard.columns(across: 390) == 2)
        #expect(Dashboard.columns(across: 844) == 4)
        #expect(Dashboard.columns(across: 1024) == 4)
        #expect(Dashboard.columns(across: 600) == 3)
    }

    @Test("never fewer than two, whatever the width")
    func narrow() {
        // A single column is a list, and a list is what the dashboard replaced.
        #expect(Dashboard.columns(across: 0) == 2)
    }

    @Test("a slip waiting is the half of it worth the square")
    func slips() {
        #expect(Dashboard.slips(waiting: 2, answered: 5) == "2 waiting")
        #expect(Dashboard.slips(waiting: 0, answered: 5) == "5 answered")
        #expect(Dashboard.slips(waiting: 0, answered: 0) == "None yet")
    }

    @Test("a subagent still going is the half of it worth the square")
    func agents() {
        // The same shape as slips, and for the same reason: the square is asked what is happening
        // now, and it falls back to what happened rather than to nothing — six finished agents
        // are six conversations still worth opening.
        #expect(Dashboard.agents(running: 2, finished: 6) == "2 running")
        #expect(Dashboard.agents(running: 0, finished: 6) == "6 finished")
        #expect(Dashboard.agents(running: 0, finished: 0) == "None yet")
    }

    @Test("nothing is said with a zero")
    func empties() {
        // The whole rule in one test: an empty tile says what is true in words. A "0" on any of
        // these reads as a number that failed to load rather than as a session that has made none.
        #expect(Dashboard.files(0) == "None yet")
        #expect(Dashboard.inbox(0) == "Empty")
        #expect(Dashboard.orders("") == "None standing")
        #expect(Dashboard.context(tokens: 0, files: 0) == "No CLAUDE.md")
        #expect(Dashboard.swapping(Replacements.Tally(swaps: 0, others: 0)) == "Nothing changed")
    }

    @Test("one of a thing is not one things")
    func singular() {
        #expect(Dashboard.files(1) == "1 file")
        #expect(Dashboard.files(14) == "14 files")
        #expect(Dashboard.inbox(1) == "1 waiting")
        #expect(Dashboard.context(tokens: 2400, files: 1) == "~2k in 1 file")
    }

    @Test("the square counts every scope, not only the chain")
    func swapping() {
        // The case the square exists for: no chain step on at all, and twelve rows of two still
        // rewriting every clip. "Nothing running" over that is the lie this replaced.
        #expect(Dashboard.swapping(Replacements.Tally(swaps: 12, others: 0)) == "12 swaps")
        // A model handed the whole sentence is not a row and is counted apart from one.
        #expect(Dashboard.swapping(Replacements.Tally(swaps: 12, others: 1))
            == "12 swaps, 1 rewrite")
        #expect(Dashboard.swapping(Replacements.Tally(swaps: 0, others: 2)) == "2 rewrites")
        #expect(Dashboard.swapping(Replacements.Tally(swaps: 1, others: 0)) == "1 swap")
    }

    @Test("orders open on their first written line, not on their first line")
    func orders() {
        // Dictated orders arrive with whatever whitespace the editor left in front of them, and
        // a blank opening line would put an empty tile over a session that is running under them.
        #expect(Dashboard.orders("\n\n  Keep the diffs small\nand say why") == "Keep the diffs small")
        #expect(Dashboard.orders("   \n\t\n") == "None standing")
        #expect(Dashboard.orders("One line only") == "One line only")
    }

    @Test("context is counted in thousands, the way the window is")
    func context() {
        #expect(Dashboard.context(tokens: 12_400, files: 7) == "~12k in 7 files")
        #expect(Dashboard.context(tokens: 640, files: 2) == "~640 in 2 files")
    }

    @Test("the model is named with its effort, or on its own, or not at all")
    func answering() {
        #expect(Dashboard.answering(family: "sonnet", effort: "high") == "sonnet high")
        #expect(Dashboard.answering(family: "sonnet", effort: nil) == "sonnet")
        #expect(Dashboard.answering(family: "sonnet", effort: "") == "sonnet")
        #expect(Dashboard.answering(family: nil, effort: "high") == nil)
    }

    @Test("a preview is three lines and never a fourth")
    func few() {
        // The cap is the grid's, not the content's: a fourth line either shrinks the type past
        // reading distance or puts back the height the preview exists to take out.
        #expect(Dashboard.few([1, 2, 3, 4, 5]) == [1, 2, 3])
        #expect(Dashboard.few([Int]()) == [])
    }

    @Test("the orders preview carries on where the headline stopped")
    func rest() {
        let orders = "\n  Keep the diffs small\n\nand say why\n\n  then stop\nand a fourth line"
        #expect(Dashboard.orders(orders) == "Keep the diffs small")
        #expect(Dashboard.rest(of: orders) == ["and say why", "then stop", "and a fourth line"])
        // A blank line is not a line. It would spend one of the three and show nothing.
        #expect(Dashboard.rest(of: "One line only") == [])
        #expect(Dashboard.rest(of: "   \n\t\n") == [])
    }

    @Test("a slip still waiting is named before one already answered")
    func asking() {
        let found = [Artifact(id: "a", title: "Old and answered", modified: 90, answered: true),
                     Artifact(id: "b", title: "Which branch", modified: 10, answered: false),
                     Artifact(id: "c", title: "Release check", modified: 20, answered: false),
                     Artifact(id: "d", title: "New and answered", modified: 99, answered: true)]
        // Waiting first however old, newest first inside each half — the same precedence the
        // count above it follows, because the square is asked the same question.
        #expect(Dashboard.asking(found) == ["Release check", "Which branch", "New and answered"])
        #expect(Dashboard.asking([]) == [])
    }

    @Test("a subagent still going is named before one that has finished")
    func doing() {
        let found = [Agent(id: "a", description: "Finished lately", running: false, updatedAt: 90),
                     Agent(id: "b", description: "Started lately", running: true, updatedAt: 20),
                     Agent(id: "c", description: "Started long ago", running: true, updatedAt: 10)]
        #expect(Dashboard.doing(found)
            == ["Started lately", "Started long ago", "Finished lately"])
        // No description is what an agent has when the session wrote none, and `kind` is the
        // fallback `Agent.title` already picked for every other surface.
        #expect(Dashboard.doing([Agent(id: "d", kind: "Explore")]) == ["Explore"])
    }

    @Test("the files preview is what was touched most recently")
    func touched() {
        let found = [Asset(path: "/a/old.swift", name: "old.swift", kind: "text",
                           size: 1, modified: 10),
                     Asset(path: "/b/new.swift", name: "new.swift", kind: "text",
                           size: 1, modified: 90)]
        #expect(Dashboard.touched(found) == ["new.swift", "old.swift"])
    }

    @Test("a filename that says nothing on its own takes the folder it sits in")
    func repeated() {
        // Found on screen: a session that had touched three CLAUDE.md files drew "CLAUDE.md"
        // three times, which says a session touched three files and nothing else at all.
        let same = ["/dev/CLAUDE.md", "/dev/deckhand/CLAUDE.md", "/dev/deckhand/one.swift"]
            .enumerated()
            .map { place, path in
                Asset(path: path, name: (path as NSString).lastPathComponent, kind: "text",
                      size: 1, modified: Double(90 - place))
            }
        // Only the repeats are widened — the file with an unambiguous name keeps it.
        #expect(Dashboard.touched(same) == ["dev/CLAUDE.md", "deckhand/CLAUDE.md", "one.swift"])
        // A file with nothing above it keeps its name rather than gaining a leading slash.
        let bare = [Asset(path: "notes.md", name: "notes.md", kind: "text", size: 1, modified: 2),
                    Asset(path: "/a/notes.md", name: "notes.md", kind: "text", size: 1,
                          modified: 1)]
        #expect(Dashboard.touched(bare) == ["notes.md", "a/notes.md"])
    }

    @Test("the chain is previewed by the names the settings sheet uses, not by its slugs")
    func running() {
        let known = [Filter(name: "max_words", title: "Word limit"),
                     Filter(name: "replacements", title: "Replacements")]
        let steps = [FilterStep(filter: "max_words", isOn: true),
                     FilterStep(filter: "replacements", isOn: false),
                     // A step naming a filter this Mac no longer offers keeps its own slug
                     // rather than vanishing, exactly as the filters sheet refuses to drop one.
                     FilterStep(filter: "gone_filter", isOn: true)]
        #expect(Dashboard.running(steps, over: known) == ["Word limit", "gone_filter"])
    }

    @Test("the family a session reports is the one the tile names")
    func family() {
        // The join to the listing: `Session.family` is what strips `claude-` and the build date,
        // and the tile says whatever that leaves rather than reading `model` itself.
        var session = Session(sessionId: "s1", pid: 1, name: "deckhand", cwd: "/dev/deckhand",
                              folder: "deckhand", status: "idle", updatedAt: 0, tty: "ttys001",
                              pane: nil)
        session.model = "claude-sonnet-5"
        session.effort = "high"
        #expect(Dashboard.answering(family: session.family, effort: session.effort) == "sonnet high")
    }
}
