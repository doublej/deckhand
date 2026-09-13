import XCTest

/// A hold on a turn opens it on a screen of its own, where a sentence can be taken out of it.
///
/// Its own file for the reason `OrdersPaneTests` is: this is not the loop through the app. It is
/// the one gesture on the transcript pane, and the class of bug it is here to catch has been paid
/// for three times in this repo — a press applied on the wrong side of something else silently
/// takes the touch. Three things have to survive on that pane at once: the paging pan under the
/// list, the vertical scroll of the list itself, and this. Nothing but the simulator can say so.
final class TurnReaderTests: XCTestCase {
    func testHoldingATurnOpensItFullScreen() throws {
        let (app, turns) = try openTheTranscript()
        add(screenshot(app, named: "transcript"))

        let held = try XCTUnwrap(onScreen(turns), "no turn is on screen to hold")
        // Long enough to be a hold and not so long that it reads as a stuck finger.
        held.press(forDuration: 0.8)
        let reader = app.descendants(matching: .any).matching(identifier: "turn-reader").firstMatch
        XCTAssertTrue(reader.waitForExistence(timeout: 5), "the hold opened nothing")
        add(screenshot(app, named: "turn-reader"))

        // A text view rather than a label is the whole point: it is what carries the handles.
        XCTAssertTrue(reader.elementType == .textView, "the reader is not a selectable text view")
        // And the turn says when it happened here too, not only on the card in the list.
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader-time")
            .firstMatch.exists, "the reader does not say when the turn was said")
        app.buttons["Close"].tap()
        XCTAssertTrue(talkMark(app).waitForExistence(timeout: 5),
                      "closing the reader left the session page")
    }

    /// The same pane, the same finger, the other meaning: a *drag* is still the list's and the
    /// page view's. This is the test that fails if the hold ever starts claiming the touch on the
    /// way down the way a sequenced gesture does.
    func testThePanesStillPageWithAHoldOnTheTurns() throws {
        let (app, _) = try openTheTranscript()

        // Backwards, because the transcript is the last pane now: past the summary is the
        // dashboard, and it has to be reachable by the same swipe as before.
        app.swipeRight()
        app.swipeRight()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "tile-slips")
            .firstMatch.waitForExistence(timeout: 10),
                      "a swipe off the transcript no longer pages")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "turn-reader")
            .firstMatch.exists, "paging opened the reader")
    }

    /// The app open on a session's transcript pane, with the turns on it.
    ///
    /// The wait on the mark is not decoration: three swipes fired before the session page exists
    /// land on the rail, and the pane never arrives.
    private func openTheTranscript() throws -> (XCUIApplication, XCUIElementQuery) {
        let app = try launch()
        let firstSession = app.descendants(matching: .any).matching(identifier: "session-row").firstMatch
        XCTAssertTrue(firstSession.waitForExistence(timeout: 30), "the deck stayed empty")
        firstSession.tap()
        XCTAssertTrue(talkMark(app).waitForExistence(timeout: 20), "the session page never opened")
        // The dashboard, the summary, the transcript — swiped to, because there is no bar at
        // the foot. The loop stops the moment turns arrive, so it is a ceiling rather than a count.
        let turns = app.descendants(matching: .staticText).matching(identifier: "turn-words")
        for _ in 0..<3 where !turns.firstMatch.exists {
            app.swipeLeft()
        }
        XCTAssertTrue(turns.firstMatch.waitForExistence(timeout: 10),
                      "no turn with words on the transcript pane — is the session empty?")
        return (app, turns)
    }

    /// The newest turn that is actually on the screen, walked backwards from the end of the list.
    ///
    /// Two things this cannot be. Not `firstMatch`: the transcript is pinned to its newest line,
    /// so the turns above are real elements sitting thousands of points off the top — measured,
    /// "Not hittable, {{32.0, -632.0}, …}". And not `allElementsBoundByAccessibilityElement`,
    /// which captures a debug description for every rendered block on the page and ran this test
    /// past its own timeout. A bounded walk from the end asks about a handful of elements and
    /// finds the one under a thumb.
    private func onScreen(_ turns: XCUIElementQuery) -> XCUIElement? {
        let last = turns.count - 1
        guard last >= 0 else { return nil }
        for index in stride(from: last, through: max(0, last - 8), by: -1) {
            let candidate = turns.element(boundBy: index)
            if candidate.isHittable { return candidate }
        }
        return nil
    }

    /// What says a session's page is up: at rest the talk control is the mark and nothing else.
    private func talkMark(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "talk-mark").firstMatch
    }

    private func launch() throws -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        let token = try XCTUnwrap(env["DECKHAND_TOKEN"], "run via `just ui-test`")
        let app = XCUIApplication()
        app.launchArguments = [
            "-deckhand.host", env["DECKHAND_HOST"] ?? "127.0.0.1:4180",
            "-deckhand.token", token,
            "-deckhand.favorites", "<array/>"
        ]
        app.launch()
        return app
    }

    private func screenshot(_ app: XCUIApplication, named name: String) -> XCTAttachment {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }
}
