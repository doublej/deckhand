import Foundation
import Testing

@testable import DeckhandKit

/// What the listing says about the Mac rather than about one session: the week's token window,
/// and what a whole rail is running. Nothing here goes near the wire — the decoding half of this
/// lives in `ClientTests`, which is where a real call is stubbed.
@Suite("The listing's Mac-wide facts")
struct ListingTests {
    private func session(_ model: String?, _ effort: String? = nil) -> Session {
        var made = Session(
            sessionId: UUID().uuidString, pid: 1, name: "n", cwd: "/c", folder: "c",
            status: "idle", updatedAt: 1, tty: "t", pane: nil
        )
        made.model = model
        made.effort = effort
        return made
    }

    @Test("every session agreeing is the model and the effort")
    func agreed() {
        let rail = [session("claude-sonnet-5", "xhigh"), session("claude-sonnet-5", "xhigh")]
        #expect(Session.running(rail) == "sonnet xhigh")
    }

    @Test("the same model at two efforts names the model and claims nothing it cannot prove")
    func sameModelTwoEfforts() {
        let rail = [session("claude-sonnet-5", "xhigh"), session("claude-sonnet-5", "low")]
        #expect(Session.running(rail) == "sonnet")
    }

    @Test("an effort only one session reports is not the rail's effort")
    func partialEffort() {
        let rail = [session("claude-sonnet-5", "xhigh"), session("claude-sonnet-5")]
        #expect(Session.running(rail) == "sonnet")
    }

    @Test("a session that has answered nothing yet neither votes nor silences the rest")
    func unansweredDoesNotCount() {
        let rail = [session("claude-sonnet-5", "xhigh"), session(nil), session(nil)]
        #expect(Session.running(rail) == "sonnet xhigh")
    }

    @Test("two models is a count, never one of them")
    func disagreed() {
        let rail = [session("claude-opus-5", "xhigh"), session("claude-sonnet-5", "xhigh")]
        #expect(Session.running(rail) == "2 models")
    }

    @Test("a rail that has answered nothing says nothing")
    func coldRail() {
        #expect(Session.running([session(nil), session(nil)]) == nil)
        #expect(Session.running([]) == nil)
    }

    @Test("a dated build is still its family, and an unfamiliar name is still its first word")
    func family() {
        #expect(session("claude-haiku-4-5-20251001").family == "haiku")
        #expect(session("claude-fable-5-1").family == "fable")
        #expect(session("something-else").family == "something")
        #expect(session("").family == nil)
    }

    @Test("a week past its budget reads as what it is rather than as full")
    func overBudget() {
        let week = Week(pctUsed: 152, pctElapsed: 51, daysRemaining: 3.5)
        #expect(week.line == "152% · 3d")
        #expect(week.overPace)
        #expect(week.spoken.contains("51 percent elapsed"))
    }

    @Test("days are whole and cut, never rounded up into time that is not there")
    func days() {
        #expect(Week(pctUsed: 8, pctElapsed: 51, daysRemaining: 3.5).days == 3)
        #expect(Week(pctUsed: 8, pctElapsed: 51, daysRemaining: 0.9).days == 0)
        #expect(Week(pctUsed: 8, pctElapsed: 51, daysRemaining: -1).days == 0)
        #expect(!Week(pctUsed: 8, pctElapsed: 51, daysRemaining: 3.5).overPace)
    }
}
