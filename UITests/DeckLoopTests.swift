import XCTest

/// Drives the app in the simulator against a running daemon: the deck lists the Mac's live
/// sessions, and opening one reaches the screen that talks back to it.
/// Needs `DECKHAND_HOST` and `DECKHAND_TOKEN` in the environment (see `just ui-test`).
final class DeckLoopTests: XCTestCase {
    func testOpeningASessionReachesTheTalkScreen() throws {
        let env = ProcessInfo.processInfo.environment
        let token = try XCTUnwrap(env["DECKHAND_TOKEN"], "run via `just ui-test`")
        let host = env["DECKHAND_HOST"] ?? "127.0.0.1:4180"

        let app = XCUIApplication()
        app.launchArguments = ["-deckhand.host", host, "-deckhand.token", token]
        app.launch()

        let firstSession = app.cells.firstMatch
        XCTAssertTrue(firstSession.waitForExistence(timeout: 15), "the deck stayed empty")
        add(screenshot(app, named: "deck"))

        firstSession.tap()
        XCTAssertTrue(
            app.staticTexts["HOLD TO TALK"].waitForExistence(timeout: 10),
            "the talk button never appeared"
        )
        add(screenshot(app, named: "session"))
    }

    private func screenshot(_ app: XCUIApplication, named name: String) -> XCTAttachment {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }
}
