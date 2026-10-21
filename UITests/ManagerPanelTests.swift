import XCTest

/// The manager panel: the two ways in, the way back, and the two things the way in must not take.
///
/// The panel is pulled in by a drag anywhere on the rail — it was a 24pt strip on the trailing
/// edge, which meant aiming at an edge to reach a screen. Nothing is overlaid and nothing is
/// taken from the rail: `ManagerShell` watches every drag with `simultaneousGesture` and moves
/// the screen for one shape of them, sideways and trailing-going.
///
/// The direction gate is the whole design, so two of these tests are the gate rather than the
/// panel. `testARowStillRevealsItsActions` fails if a leading-going drag stops belonging to the
/// row it started on; `testAVerticalSwipeIsTheListsAndNotThePanels` fails if a drag up the page
/// starts moving the screen sideways. Either one breaking makes the panel not worth having.
///
/// Needs `DECKHAND_HOST` and `DECKHAND_TOKEN` in the environment (see `just ui-test`).
final class ManagerPanelTests: XCTestCase {
    /// The panel is recognised by its mark, `manager-talk-mark`, which is on this screen and on no other. Not by an
    /// identifier on the panel's own container: SwiftUI pushes one of those down onto every
    /// descendant, so the field and both buttons came back wearing the container's name.
    func testTheGlyphOpensThePanel() throws {
        let app = try launch()
        let panel = app.descendants(matching: .any)["manager-talk-mark"]
        let opener = app.buttons["open-manager"]
        XCTAssertTrue(opener.waitForExistence(timeout: 20), "the rail's foot has no way in")
        opener.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "the glyph opened nothing")
        add(screenshot(app, named: "manager"))
    }

    /// The gesture JJ asked for: a drag begun in the middle of the screen, nowhere near an edge,
    /// and the whole screen follows it. This is the one that fails against a strip.
    func testASwipeFromTheMiddleOpensThePanel() throws {
        let app = try launch()
        let row = app.descendants(matching: .any).matching(identifier: "session-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the rail stayed empty")

        drag(app, from: 0.5, to: 0.05)
        waitForPanel(app, onScreen: true)

        // And back out the same way, from the middle of the panel rather than its edge — from the
        // tray, because on the manager's half that drag turns the page instead.
        app.buttons["manager-tab-tray"].tap()
        drag(app, from: 0.5, to: 0.95)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the panel would not go away again")
    }

    /// The halves are swiped between, and the drag out is the halves' until the tray shows: one
    /// sideways drag must never turn the page and put the drawer away at once.
    func testASwipeTurnsBetweenTheHalvesBeforeItLeaves() throws {
        let app = try launch()
        let opener = app.buttons["open-manager"]
        XCTAssertTrue(opener.waitForExistence(timeout: 20), "the rail's foot has no way in")
        opener.tap()
        waitForPanel(app, onScreen: true)
        let tray = app.buttons["manager-tab-tray"]
        let manager = app.buttons["manager-tab-manager"]

        tray.tap()
        drag(app, from: 0.7, to: 0.2)
        XCTAssertTrue(manager.waitForSelection(), "a swipe on the tray did not turn to the manager")

        drag(app, from: 0.3, to: 0.8)
        XCTAssertTrue(tray.waitForSelection(), "a swipe on the manager did not turn to the tray")
        waitForPanel(app, onScreen: true)

        drag(app, from: 0.3, to: 0.95)
        waitForPanel(app, onScreen: false)
    }

    /// The edge still works. "Anywhere" has to include the place it used to be the only place.
    func testTheTrailingEdgeStillSwipesThePanelIn() throws {
        let app = try launch()
        let row = app.descendants(matching: .any).matching(identifier: "session-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the rail stayed empty")

        drag(app, from: 0.995, to: 0.15)
        waitForPanel(app, onScreen: true)
    }

    /// A drag up the page is the list's, and the screen must not follow it sideways. This is what
    /// a strip bought by being 24 points wide and what the direction gate buys instead.
    func testAVerticalSwipeIsTheListsAndNotThePanels() throws {
        let app = try launch()
        let row = app.descendants(matching: .any).matching(identifier: "session-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the rail stayed empty")

        app.swipeUp()
        app.swipeDown()
        waitForPanel(app, onScreen: false, timeout: 2)
        XCTAssertTrue(row.exists, "the rail went somewhere it was not sent")
    }

    /// Every row action lives on the leading edge now, which is what leaves the trailing drag
    /// free for the screen. A leading-going drag is still the row's, from anywhere on it.
    func testARowStillRevealsItsActions() throws {
        let app = try launch()
        let row = app.descendants(matching: .any).matching(identifier: "session-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the rail stayed empty")
        row.swipeRight()
        let star = app.buttons.matching(
            NSPredicate(format: "label == 'Star' OR label == 'Unstar'")
        ).firstMatch
        XCTAssertTrue(star.waitForExistence(timeout: 5),
                      "the panel gesture took the row's own swipe")
        let hide = app.buttons.matching(
            NSPredicate(format: "label == 'Hide' OR label == 'Show'")
        ).firstMatch
        XCTAssertTrue(hide.exists, "hiding lost its home when it moved off the trailing edge")
    }

    /// The whole loop, against the Mac that is actually running: the words go up, the Mac writes
    /// them down, and the panel's next poll brings them back as a card. It costs the manager one
    /// short run, which is the price of proving the only thing the wire tests cannot.
    func testWhatIsTypedReachesTheMac() throws {
        let app = try launch()
        let opener = app.buttons["open-manager"]
        XCTAssertTrue(opener.waitForExistence(timeout: 20), "the rail's foot has no way in")
        opener.tap()

        // Typing is behind the mark's long press, as on a session's page.
        let mark = app.descendants(matching: .any)["manager-talk-mark"]
        XCTAssertTrue(mark.waitForExistence(timeout: 5), "the panel has no mark")
        mark.press(forDuration: 1.0)
        app.buttons["Type"].tap()
        let field = app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Type opened nothing to type into")
        field.typeText("say ok")
        app.buttons["Done"].tap()

        let card = app.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label CONTAINS[c] 'say ok'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15),
                      "what was said never came back onto the panel")
        add(screenshot(app, named: "manager-said"))
    }

    /// On screen, not merely in the hierarchy.
    ///
    /// Both halves of the shell are mounted the whole time — the panel is one screen's width off
    /// to the side — so its mark `exists` whether or not it has been pulled in, and a test that
    /// asked would pass without the gesture ever working. Hittability is what tells them apart.
    private func waitForPanel(_ app: XCUIApplication, onScreen: Bool, timeout: TimeInterval = 5) {
        let field = app.descendants(matching: .any)["manager-talk-mark"]
        let wanted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == %@", NSNumber(value: onScreen)),
            object: field
        )
        XCTAssertEqual(XCTWaiter().wait(for: [wanted], timeout: timeout), .completed,
                       onScreen ? "the panel did not come in" : "the panel came in uninvited")
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

private extension XCUIElement {
    /// Whether this tab comes to say it is the one showing, within a page turn's time.
    func waitForSelection(timeout: TimeInterval = 3) -> Bool {
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"), object: self)
        return XCTWaiter().wait(for: [selected], timeout: timeout) == .completed
    }
}
