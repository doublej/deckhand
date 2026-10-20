import Foundation
import Testing

@testable import DeckhandKit

/// What was said to a slip before it was sent, and what makes it worth throwing away.
@Suite("SlipDrafts")
struct SlipDraftsTests {
    @Test("a draft is read back exactly as it was set")
    func remembers() {
        var drafts = SlipDrafts()
        drafts.set(["scope": "all of it", "when": "Thursday"], for: "release-check")
        #expect(drafts.draft(for: "release-check") == ["scope": "all of it", "when": "Thursday"])
        // A slip nobody has touched has nothing to say about it.
        #expect(drafts.draft(for: "which-branch").isEmpty)
    }

    @Test("a blank answer is not a draft worth keeping")
    func dropsBlanks() {
        var drafts = SlipDrafts()
        drafts.set(["scope": "all of it", "when": "   "], for: "release-check")
        #expect(drafts.draft(for: "release-check") == ["scope": "all of it"])
        // Setting a slip to nothing but blanks removes it rather than leaving an empty entry.
        drafts.set(["scope": " "], for: "release-check")
        #expect(drafts.byArtifact["release-check"] == nil)
    }

    @Test("clearing a slip that was never drafted does nothing")
    func clears() {
        var drafts = SlipDrafts()
        drafts.set(["scope": "all of it"], for: "release-check")
        drafts.clear("release-check")
        #expect(drafts.draft(for: "release-check").isEmpty)
        drafts.clear("never-touched")
        #expect(drafts.byArtifact.isEmpty)
    }

    @Test("a draft survives a round trip through UserDefaults")
    func roundTrips() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        var drafts = SlipDrafts.load(from: defaults)
        #expect(drafts.byArtifact.isEmpty)
        drafts.set(["scope": "all of it"], for: "release-check")
        drafts.save(to: defaults)
        #expect(SlipDrafts.load(from: defaults).draft(for: "release-check") == ["scope": "all of it"])
    }

    @Test("a web slip's draft is its own JSON, and null or too much is none")
    func keepsPages() {
        var drafts = SlipDrafts()
        #expect(drafts.page(for: "cue-points") == "null")
        drafts.setPage(#"{"cues":[12.5,40]}"#, for: "cue-points")
        #expect(drafts.page(for: "cue-points") == #"{"cues":[12.5,40]}"#)
        drafts.setPage("null", for: "cue-points")
        #expect(drafts.pages.isEmpty)
        drafts.setPage("\"" + String(repeating: "x", count: SlipDrafts.pageLimit) + "\"", for: "cue-points")
        #expect(drafts.pages.isEmpty)
        // A send clears both halves.
        drafts.setPage("[1]", for: "cue-points")
        drafts.clear("cue-points")
        #expect(drafts.pages.isEmpty)
    }

    @Test("a web slip's draft survives a round trip through UserDefaults")
    func pagesRoundTrip() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        var drafts = SlipDrafts()
        drafts.setPage("[1,2]", for: "cue-points")
        drafts.save(to: defaults)
        #expect(SlipDrafts.load(from: defaults).page(for: "cue-points") == "[1,2]")
    }
}
