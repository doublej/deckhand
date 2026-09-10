import Foundation
import Testing

@testable import DeckhandKit

/// The artifact wire, and the injection that is the whole security boundary of the feature.
///
/// No web view in here on purpose: `ArtifactPage` is pure string work precisely so that the one
/// thing that must never quietly stop working can be tested on the Mac, in milliseconds, without
/// a simulator.
@Suite("Artifacts")
struct ArtifactTests {
    private let style = "/* deckhand tokens */ body { color: red }"

    @Test("the listing decodes through the same snake-case decoder the client uses")
    func decodesListing() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let list = try decoder.decode(ArtifactList.self, from: Data("""
        {"artifacts":[{"id":"release-check","title":"Release check",
                       "modified":1757500000.0,"answered":false},
                      {"id":"which-branch","title":"Which branch?",
                       "modified":1757400000.0,"answered":true}]}
        """.utf8))
        #expect(list.artifacts.count == 2)
        #expect(list.artifacts.first?.id == "release-check")
        #expect(list.artifacts.first?.answered == false)
        #expect(list.artifacts.last?.answered == true)
        #expect(list.artifacts.first?.changed == Date(timeIntervalSince1970: 1_757_500_000))
    }

    @Test("a Mac with nothing to show, and one that has never heard of artifacts, read the same")
    func decodesAbsence() throws {
        // The `Session.context` case: a missing key is not a broken answer. The other half of
        // this — a 404 from a daemon with no such route — is in the client's own tests.
        #expect(try JSONDecoder().decode(ArtifactList.self, from: Data("{}".utf8)).artifacts.isEmpty)
        let empty = try JSONDecoder().decode(ArtifactList.self, from: Data(#"{"artifacts":[]}"#.utf8))
        #expect(empty.artifacts.isEmpty)
    }

    @Test("the policy is the one in docs/artifacts.md, clause for clause")
    func policyHasNotDrifted() {
        // Restated here rather than derived, so that editing either copy fails this.
        #expect(ArtifactPage.policy == "default-src 'none'; style-src 'unsafe-inline'; "
            + "script-src 'unsafe-inline'; img-src data:; font-src data:; "
            + "form-action 'none'; base-uri 'none'")
    }

    @Test("the policy lands before the page's first script, and before its first style")
    func policyComesFirst() throws {
        let page = """
        <!DOCTYPE html><html><head><style>body{color:blue}</style>
        <script>window.ran = true</script></head><body>Pick one</body></html>
        """
        let armoured = ArtifactPage.armoured(page, style: style)
        let csp = try #require(armoured.range(of: "Content-Security-Policy"))
        let ours = try #require(armoured.range(of: style))
        let script = try #require(armoured.range(of: "<script"))
        let theirs = try #require(armoured.range(of: "<style>body"))
        #expect(csp.lowerBound < script.lowerBound)
        #expect(ours.lowerBound < theirs.lowerBound)
        // The page itself is untouched — armouring adds, it never edits.
        #expect(armoured.contains("Pick one"))
    }

    @Test("a page that opens with a script, before any head, is still policed")
    func policesAHeadlessPage() throws {
        // The reason the injection is prepended rather than spliced into `<head>`: a script
        // before any head tag is hoisted into the head by the parser, which would put it above
        // anything inserted after a `<head>` that comes later in the text.
        let page = "<script>window.ran = true</script><head><title>Sneaky</title></head>"
        let armoured = ArtifactPage.armoured(page, style: style)
        let csp = try #require(armoured.range(of: "Content-Security-Policy"))
        let script = try #require(armoured.range(of: "<script"))
        #expect(csp.lowerBound < script.lowerBound)
        #expect(armoured.contains("<title>Sneaky</title>"))
    }

    @Test("a page's own policy is narrowed by ours rather than replacing it")
    func keepsBothPolicies() throws {
        let page = """
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src *">
        </head><body>hi</body></html>
        """
        let armoured = ArtifactPage.armoured(page, style: style)
        // Both are present — a browser intersects them — and ours is the one that is read first.
        #expect(armoured.contains("default-src *"))
        let ours = try #require(armoured.range(of: "default-src 'none'"))
        let theirs = try #require(armoured.range(of: "default-src *"))
        #expect(ours.lowerBound < theirs.lowerBound)
    }

    @Test("the doctype stays in front, and a page without one is given one")
    func keepsTheDoctypeFirst() {
        let declared = ArtifactPage.armoured("<!doctype html>\n<html><body>hi</body></html>",
                                             style: style)
        #expect(declared.hasPrefix("<!doctype html>\n<meta http-equiv"))
        // One doctype, not two: the page's own is reused where it is.
        #expect(declared.components(separatedBy: "<!doctype").count == 2)
        // Without one a page would be laid out in quirks mode, which the stylesheet was not
        // written for.
        #expect(ArtifactPage.armoured("<p>just a fragment</p>", style: style)
            .hasPrefix("<!DOCTYPE html>\n<meta http-equiv"))
    }

    @Test("leading whitespace and a byte-order mark do not get in front of the doctype")
    func skipsRubbishBeforeTheDoctype() {
        let armoured = ArtifactPage.armoured("\u{FEFF}\n  <!DOCTYPE html><html></html>",
                                             style: style)
        #expect(armoured.hasPrefix("<!DOCTYPE html>\n<meta http-equiv"))
        #expect(!armoured.contains("\u{FEFF}"))
    }

    @Test("the bridge hands over the artifact and stringifies the answer")
    func bridgeIsWhatTheDocPromises() {
        let page = Artifact(id: "pick-one", title: "Pick one", modified: 1, answered: false)
        let injected = ArtifactPage.bridge(for: page)
        #expect(injected.contains(#""id":"pick-one""#))
        #expect(injected.contains("post({ kind: 'respond', json: JSON.stringify(value) })"))
        // Nothing is not an answer, and the Mac refuses one: the page is told so where the agent
        // that wrote it will see it, rather than the person being shown a 422.
        #expect(injected.contains("value === undefined || value === null"))
        #expect(injected.contains("new TypeError"))
        #expect(injected.contains("messageHandlers.deckhand.postMessage"))
        // Frozen, because a page overwriting `respond` would break the only way off the screen.
        #expect(injected.contains("Object.freeze"))
        #expect(injected.contains("configurable: false"))
    }

    @Test("the bridge carries last time's answer, in the page's own shape")
    func bridgeCarriesThePreviousAnswer() {
        let page = Artifact(id: "footer", title: "What the footer should say", modified: 1,
                            answered: true)
        let said = ArtifactPage.bridge(for: page, answer: #"{"line":"Made on a boat"}"#)
        #expect(said.contains(#"answer: {"line":"Made on a boat"}"#))
        // Not frozen, unlike `artifact`: a page prefills its controls from this and the person
        // then edits, which a frozen object would refuse.
        #expect(!said.contains(#"Object.freeze({"line""#))
        // Nobody has answered, and a page with no argument at all reads the same way.
        #expect(ArtifactPage.bridge(for: page, answer: "null").contains("answer: null,"))
        #expect(ArtifactPage.bridge(for: page).contains("answer: null,"))
    }

    @Test("an empty answer cannot leave the bridge a syntax error")
    func bridgeSurvivesAnEmptyAnswer() {
        let page = Artifact(id: "footer", title: "Footer", modified: 1, answered: true)
        // `answer: ,` would take `window.deckhand` with it, and the page's only way to answer
        // with it — so emptiness becomes the absence it means.
        #expect(ArtifactPage.bridge(for: page, answer: "").contains("answer: null,"))
        #expect(ArtifactPage.bridge(for: page, answer: "  \n ").contains("answer: null,"))
        // A real value keeps its own whitespace trimmed off and nothing else.
        #expect(ArtifactPage.bridge(for: page, answer: " [1,2] \n").contains("answer: [1,2],"))
    }

    @Test("a title with a quote in it cannot end the bridge early")
    func bridgeEscapesATitle() {
        let page = Artifact(id: "x", title: "He said \"no\"\nagain", modified: 1, answered: false)
        let injected = ArtifactPage.bridge(for: page)
        #expect(injected.contains(#"\"no\""#))
        #expect(injected.contains("\\n"))
        // The raw newline would have put the rest of the object on its own line, where it is a
        // syntax error and `window.deckhand` never exists.
        #expect(!injected.contains("\"no\"\nagain"))
    }
}
