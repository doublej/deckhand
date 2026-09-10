import XCTest

/// The manager panel: the two ways in, the way back, and the thing the way in nearly broke.
///
/// The gesture is a strip overlaid on the trailing edge of the rail, which is the same shape
/// `SessionView`'s back gesture uses and for the same reason — the rows underneath already spend
/// their horizontal drag on `swipeActions`. `testARowStillRevealsItsActions` is the test that
/// fails if the strip ever grows wide enough to take that drag, which is the whole risk of
/// putting a gesture on this page at all.
///
/// Needs `DECKHAND_HOST` and `DECKHAND_TOKEN` in the environment (see `just ui-test`).
final class ManagerPanelTests: XCTestCase {
    /// The panel is recognised by its field, which is on this screen and on no other. Not by an
    /// identifier on the panel's own container: SwiftUI pushes one of those down onto every
    /// descendant, so the field and both buttons came back wearing the container's name.
    func testTheGlyphOpensThePanel() throws {
        let app = try launch()
        let panel = app.textFields["manager-field"]
        let opener = app.buttons["open-manager"]
        XCTAssertTrue(opener.waitForExistence(timeout: 20), "the rail's foot has no way in")
        opener.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "the glyph opened nothing")
        add(screenshot(app, named: "manager"))
    }

    /// The gesture JJ asked for: everything moves left and the panel is behind it.
    func testTheTrailingEdgeSwipesThePanelIn() throws {
        let app = try launch()
        let row = app.descendants(matching: .any).matching(identifier: "session-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the rail stayed empty")

        drag(app, from: 0.995, to: 0.15)
        let panel = app.textFields["manager-field"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "a trailing edge drag did not open it")

        // And back out the way it came, from the panel's own leading edge.
        drag(app, from: 0.005, to: 0.85)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the panel would not go away again")
    }

    /// The strip is drawn over the rows, so it takes the touch before the `List` sees it. It is
    /// 24 points wide for exactly this reason: a row swiped anywhere else still reveals its
    /// actions. This is the regression that would make the panel not worth having.
    func testARowStillRevealsItsActions() throws {
        let app = try launch()
        let row = app.descendants(matching: .any).matching(identifier: "session-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the rail stayed empty")
        row.swipeRight()
        let star = app.buttons.matching(
            NSPredicate(format: "label == 'Star' OR label == 'Unstar'")
        ).firstMatch
        XCTAssertTrue(star.waitForExistence(timeout: 5),
                      "the manager strip took the row's own swipe")
    }

    /// The whole loop, against the Mac that is actually running: the words go up, the Mac writes
    /// them down, and the panel's next poll brings them back as a card. It costs the manager one
    /// short run, which is the price of proving the only thing the wire tests cannot.
    func testWhatIsTypedReachesTheMac() throws {
        let app = try launch()
        let opener = app.buttons["open-manager"]
        XCTAssertTrue(opener.waitForExistence(timeout: 20), "the rail's foot has no way in")
        opener.tap()

        // Not `app.textFields`: a `TextField(axis: .vertical)` is a text *view* to the
        // accessibility hierarchy, so asking for the wrong kind finds nothing and reads as a
        // panel with no field on it.
        let field = app.textFields["manager-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the panel has nothing to type into")
        field.tap()
        field.typeText("say ok")
        app.buttons["manager-send"].tap()

        let card = app.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label CONTAINS[c] 'say ok'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15),
                      "what was said never came back onto the panel")
        add(screenshot(app, named: "manager-said"))
    }

    /// A drag across the middle of the screen, from one fraction of the width to another.
    private func drag(_ app: XCUIApplication, from start: CGFloat, to end: CGFloat) {
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: start, dy: 0.5))
        let across = app.coordinate(withNormalizedOffset: CGVector(dx: end, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: across)
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
