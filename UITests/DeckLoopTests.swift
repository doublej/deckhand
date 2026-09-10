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
        // The mark, not a label: at rest the talk control is the mark and nothing else — no
        // bar, no caption — so the mark is what says this is a session's page.
        let talk = app.descendants(matching: .any).matching(identifier: "talk-mark").firstMatch
        let appeared = talk.waitForExistence(timeout: 15)
        add(screenshot(app, named: "session"))
        XCTAssertTrue(appeared, "the talk button never appeared")

        // The other panes are their own screens and are worth seeing on their own. Swiped to,
        // not tapped: the bar of tabs at the foot is gone and the four panes sit side by side,
        // which is the one thing this test can prove still works.
        for pane in ["slips", "transcript", "files"] {
            app.swipeLeft()
            add(screenshot(app, named: pane))
        }
        // A swipe in the content pages and does not leave: the mark is still here, and the
        // fourth pane is the one we landed on.
        XCTAssertTrue(talk.exists, "the mark went away while paging")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "file-filter")
            .firstMatch.waitForExistence(timeout: 10), "three swipes did not reach Files")
        // And the one control the way out must never take a touch from. The mark floats over
        // the panes and does not reach into the leading 20 points the edge strip lives in.
        XCTAssertGreaterThan(talk.frame.minX, 20, "the talk mark reaches into the edge strip")
    }

    /// The way out is a drag from the leading edge, and it has to work from every pane. On any
    /// but the first, the page view under it wants that same drag — this is the test that fails
    /// if it ever gets it.
    func testTheLeadingEdgeLeavesTheSessionFromEveryPane() throws {
        let app = try launch()
        let firstSession = app.descendants(matching: .any).matching(identifier: "session-row").firstMatch
        let talk = app.descendants(matching: .any).matching(identifier: "talk-mark").firstMatch
        XCTAssertTrue(firstSession.waitForExistence(timeout: 20), "the deck stayed empty")

        for paged in 0..<4 {
            firstSession.tap()
            XCTAssertTrue(talk.waitForExistence(timeout: 15), "the session never opened")
            for _ in 0..<paged { app.swipeLeft() }
            drag(app, from: 0.01, to: 0.75)
            XCTAssertTrue(firstSession.waitForExistence(timeout: 5),
                          "an edge swipe on pane \(paged) did not leave the session")
        }
    }

    /// One drag does one thing. A drag from the edge that is too short to leave must not page
    /// either — if the page view were seeing the touch as well, a fling that size would take it.
    func testAnEdgeDragTooShortToLeaveDoesNotPageEither() throws {
        let app = try launch()
        let firstSession = app.descendants(matching: .any).matching(identifier: "session-row").firstMatch
        XCTAssertTrue(firstSession.waitForExistence(timeout: 20), "the deck stayed empty")
        firstSession.tap()
        let files = app.descendants(matching: .any).matching(identifier: "file-filter").firstMatch
        for _ in 0..<3 { app.swipeLeft() }
        XCTAssertTrue(files.waitForExistence(timeout: 15), "three swipes did not reach Files")

        drag(app, from: 0.01, to: 0.14)
        let talk = app.descendants(matching: .any).matching(identifier: "talk-mark").firstMatch
        XCTAssertTrue(talk.exists, "a short edge drag left the session")
        XCTAssertTrue(files.exists, "a short edge drag paged instead of doing nothing")
    }

    /// A drag across the middle of the page, from one fraction of the width to another.
    private func drag(_ app: XCUIApplication, from start: CGFloat, to end: CGFloat) {
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: start, dy: 0.5))
        let across = app.coordinate(withNormalizedOffset: CGVector(dx: end, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: across)
    }

    /// A press is how you talk to a session without opening it, so a press must not open it:
    /// a row is a button, and a button fires on release however long the finger was down.
    func testHoldingARowTalksToItRatherThanOpeningIt() throws {
        let app = try launch()
        let firstSession = app.descendants(matching: .any).matching(identifier: "session-row").firstMatch
        XCTAssertTrue(firstSession.waitForExistence(timeout: 20), "the deck stayed empty")

        firstSession.press(forDuration: 1.2)
        let talk = app.descendants(matching: .any).matching(identifier: "talk-mark").firstMatch
        XCTAssertFalse(talk.waitForExistence(timeout: 3), "a press on a row opened the session")
        XCTAssertTrue(firstSession.exists, "the sessions list went away")
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
