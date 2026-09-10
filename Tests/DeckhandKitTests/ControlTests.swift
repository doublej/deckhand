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

    @Test("the two that cannot be undone ask first, and the two that can do not")
    func asking() {
        #expect(Control.clear.asksFirst)
        #expect(Control.exit.asksFirst)
        #expect(!Control.cancel.asksFirst)
        #expect(!Control.compact.asksFirst)
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

        #expect(Control.cancel.caution(about: "deckhand") == nil)
        #expect(Control.compact.caution(about: "deckhand") == nil)
    }

    @Test("every control has a label and a glyph, including any added later")
    func dressed() {
        for action in Control.allCases {
            #expect(!action.label.isEmpty)
            #expect(!action.symbol.isEmpty)
        }
    }
}
