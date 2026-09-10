import XCTest

/// The last pane of a session: what it has been told to keep in mind.
///
/// Its own file rather than another case in `DeckLoopTests`, which is one loop through the app and
/// stops where it started. This goes past the end of that loop — the orders pane is the one you
/// swipe to and it is the one nothing else here reaches.
///
/// Nothing is typed into a session by this test. It swipes to the pane, reads what is standing and
/// opens the field; the saving half needs a daemon carrying the route, and a UI test that wrote a
/// paragraph into a live session's orders would leave it there.
final class OrdersPaneTests: XCTestCase {
    func testTheLastPaneIsTheSessionsOrders() throws {
        let app = try launch()
        let firstSession = app.descendants(matching: .any).matching(identifier: "session-row").firstMatch
        XCTAssertTrue(firstSession.waitForExistence(timeout: 30), "the deck stayed empty")
        firstSession.tap()
        let talk = app.descendants(matching: .any).matching(identifier: "talk-mark").firstMatch
        XCTAssertTrue(talk.waitForExistence(timeout: 20), "the session page never opened")

        // Past summary, slips, transcript and files. One more than the loop test walks, because
        // orders is deliberately last: the pane you land on stays the briefing.
        let card = app.descendants(matching: .any).matching(identifier: "orders-card").firstMatch
        for _ in 0..<4 where !card.exists {
            app.swipeLeft()
        }
        XCTAssertTrue(card.waitForExistence(timeout: 5), "no orders pane at the end of the panes")
        add(screenshot(app, named: "orders"))
        // The mark still floats over it: this pane is inside the session page like the other four.
        XCTAssertTrue(talk.exists, "the mark went away on the orders pane")

        // The whole card is the way in, and what it opens is `Editor` — a field with the app's own
        // talk control under it, which is why there is no second one on the pane itself.
        card.tap()
        let field = app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the card opened no field")
        add(screenshot(app, named: "orders-editing"))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "say-into").firstMatch.exists,
                      "the field cannot be spoken into")
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
