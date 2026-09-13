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
        #expect(Dashboard.chain(running: 0, of: 6) == "Nothing running")
        #expect(Dashboard.chain(running: 0, of: 0) == "None offered")
    }

    @Test("one of a thing is not one things")
    func singular() {
        #expect(Dashboard.files(1) == "1 file")
        #expect(Dashboard.files(14) == "14 files")
        #expect(Dashboard.inbox(1) == "1 waiting")
        #expect(Dashboard.context(tokens: 2400, files: 1) == "~2k in 1 file")
    }

    @Test("the chain says what it runs out of")
    func chain() {
        #expect(Dashboard.chain(running: 3, of: 6) == "3 of 6 running")
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
