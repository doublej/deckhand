import XCTest

/// Drives the app in the simulator against a running daemon: the deck lists the Mac's live
/// sessions, a session opens onto the talk screen, and landscape turns favourites into columns.
/// Needs `DECKHAND_HOST` and `DECKHAND_TOKEN` in the environment (see `just ui-test`).
final class DeckLoopTests: XCTestCase {
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testOpeningASessionReachesTheTalkScreen() throws {
        let app = try launch()
        let firstSession = app.descendants(matching: .any).matching(identifier: "session-row").firstMatch
        XCTAssertTrue(firstSession.waitForExistence(timeout: 20), "the deck stayed empty")
        add(screenshot(app, named: "deck"))

        firstSession.tap()
        let talk = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'TO TALK' OR label CONTAINS 'RECORDING'")
        ).firstMatch
        let appeared = talk.waitForExistence(timeout: 15)
        add(screenshot(app, named: "session"))
        XCTAssertTrue(appeared, "the talk button never appeared")
    }

    func testTheConnectionIsAlwaysStated() throws {
        let app = try launch()
        // Whatever happens, the bar says something: connected, reaching, or why not.
        let bar = app.descendants(matching: .any).matching(
            NSPredicate(format: "label IN {'ON', 'WAIT', 'ERR', 'OFF'}")
        )
        XCTAssertTrue(bar.firstMatch.waitForExistence(timeout: 20), "no connection status shown")
    }

    func testStarredSessionsBecomeLandscapeColumns() throws {
        let app = try launch()
        let firstSession = app.descendants(matching: .any).matching(identifier: "session-row").firstMatch
        XCTAssertTrue(firstSession.waitForExistence(timeout: 20), "the deck stayed empty")
        firstSession.swipeRight()
        let star = app.buttons.matching(
            NSPredicate(format: "label == 'Star' OR label == 'Unstar'")
        ).firstMatch
        XCTAssertTrue(star.waitForExistence(timeout: 5), "no star action on the row")
        if star.label == "Star" { star.tap() } else { app.tap() }

        XCUIDevice.shared.orientation = .landscapeLeft
        let column = app.descendants(matching: .any).matching(identifier: "deck-column").firstMatch
        let appeared = column.waitForExistence(timeout: 10)
        add(screenshot(app, named: "landscape"))
        XCTAssertTrue(appeared, "landscape showed no columns")
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
