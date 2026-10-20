import XCTest

/// What a session has been told to keep in mind, reached from the square that says so.
///
/// Its own file rather than another case in `DeckLoopTests`, which is one loop through the app and
/// stops where it started. This goes off that loop — the orders pane is a sheet now, opened from
/// the dashboard, and it is the one nothing else here reaches.
///
/// Nothing is typed into a session by this test. It opens the square, reads what is standing and
/// opens the field; the saving half needs a daemon carrying the route, and a UI test that wrote a
/// paragraph into a live session's orders would leave it there.
final class OrdersPaneTests: XCTestCase {
    func testTheOrdersSquareOpensTheSessionsOrders() throws {
        let app = try launch()
        let firstSession = app.descendants(matching: .any).matching(identifier: "session-row").firstMatch
        XCTAssertTrue(firstSession.waitForExistence(timeout: 30), "the deck stayed empty")
        firstSession.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "talk-mark").firstMatch
            .waitForExistence(timeout: 20), "the session page never opened")

        // A square on the dashboard rather than four swipes to the end of a carousel. The tile
        // says what is standing before anything is opened, which is the whole reason it is one.
        let tile = app.descendants(matching: .any).matching(identifier: "tile-orders").firstMatch
        app.swipeLeft()
        XCTAssertTrue(tile.waitForExistence(timeout: 15), "no orders square on the dashboard")
        tile.tap()

        let card = app.descendants(matching: .any).matching(identifier: "orders-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the orders square opened nothing")
        add(screenshot(app, named: "orders"))
        // It arrives on a sheet, which means it arrives with a way off it — the pane was written
        // to sit under a header that named the session and would otherwise have no title at all.
        XCTAssertTrue(app.buttons["Done"].exists, "the orders sheet has no way off it")

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
