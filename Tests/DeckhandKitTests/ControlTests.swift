import Foundation
import Testing

@testable import DeckhandKit

@Suite("The things you do to a session rather than say to it")
struct ControlTests {
    /// The other half of a join nothing else checks. `deliver.CONTROLS` on the Mac is keyed by
    /// these exact words, and the two lists are in different languages with no compiler between
    /// them: a control added here and not there is a menu item that reaches the daemon and comes
    /// back "no such control", which reads as a broken session rather than a missing line.
    /// `test_every_control_the_phone_offers_is_one_the_daemon_knows` asserts the same four.
    @Test("the wire words are the daemon's keys, in the order the menu shows them")
    func wire() {
        #expect(Control.allCases.map(\.rawValue) == ["cancel", "compact", "clear", "exit"])
    }

    @Test("three ask first, and only stopping a run does not")
    func asking() {
        #expect(Control.clear.asksFirst)
        #expect(Control.exit.asksFirst)
        #expect(Control.compact.asksFirst)
        // Escape only ever takes work away and the session is still there afterwards, so it is
        // the one control a thumb may fire straight off the grid.
        #expect(!Control.cancel.asksFirst)
    }

    /// The two sets were equal once and one property did both jobs, which is why compacting
    /// arrived on the grid ungated. Asking first is a sentence and a second tap; being
    /// irreversible is what earns a control the menu's red section instead of a square.
    @Test("asking first is not the same question as cannot be undone")
    func irreversible() {
        #expect(Control.clear.isIrreversible)
        #expect(Control.exit.isIrreversible)
        #expect(!Control.cancel.isIrreversible)
        // The whole point of the split: compact asks, and is still not in this set.
        #expect(Control.compact.asksFirst && !Control.compact.isIrreversible)
    }

    /// The bug this is here to stop: the confirmation sheet was written for `clear` alone, so a
    /// second control that needed confirming would have asked "Clear this?" before quitting
    /// Claude Code. Every control that asks has to bring its own question.
    @Test("each question names the session and says what it costs")
    func questions() {
        let clearing = Control.clear.caution(about: "deckhand")
        #expect(clearing?.title == "Clear deckhand?")
        #expect(clearing?.because.contains("no undo") == true)

        let ending = Control.exit.caution(about: "deckhand")
        #expect(ending?.title == "End deckhand?")
        #expect(ending?.verb == "End the session")
        // What a person needs to know before pressing it: this phone cannot undo it.
        #expect(ending?.because.contains("Only the Mac") == true)

        // What compacting costs, in the words somebody needs before pressing it. Not "there is
        // no undo", which is `clear`'s sentence and would read as the same thing happening.
        let folding = Control.compact.caution(about: "deckhand")
        #expect(folding?.title == "Compact deckhand?")
        #expect(folding?.verb == "Compact the conversation")
        #expect(folding?.because.contains("folded into one summary") == true)
        #expect(folding?.because.contains("detail") == true)

        #expect(Control.cancel.caution(about: "deckhand") == nil)
    }

    /// The one thing on the dashboard worth confirming that is not a `Control`. Its words are
    /// held down here because the risk is the sentence rather than the plumbing: the daemon
    /// writes a timestamp and Claude Code's transcript is never touched, so a caution borrowing
    /// `clear`'s "no undo" would be a scarier sentence about a smaller thing.
    @Test("clearing an inbox says what it drops and says the conversation is fine")
    func inbox() {
        let asked = Caution.clearingInbox(of: "deckhand")
        #expect(asked.title == "Clear deckhand's inbox?")
        #expect(asked.verb == "Clear the inbox")
        #expect(asked.because.contains("dropped"))
        #expect(asked.because.contains("never read them"))
        // The reassurance is the half that stops this reading as `clear`.
        #expect(asked.because.contains("already said is untouched"))
        // And it must not claim what only `clear` claims.
        #expect(!asked.because.contains("no undo"))
    }

    @Test("every control has a label and a glyph, including any added later")
    func dressed() {
        for action in Control.allCases {
            #expect(!action.label.isEmpty)
            #expect(!action.symbol.isEmpty)
        }
    }
}
