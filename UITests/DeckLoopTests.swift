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

    /// Four presentations hang off one view in `SessionFoot` — two sheets, this dialog, and the
    /// photo picker, which is itself a sheet. Multiple sheets on one view have been supported
    /// since iOS 16, but that is exactly the place iOS goes quietly unreliable, and a picker that
    /// silently opens nothing looks identical to a button nobody wired up. So it is asserted
    /// rather than reasoned about.
    ///
    /// The gesture is a **tap** on the mark, not a hold, and that is not a mistake: talking is the
    /// hold in the default mode, so the other three things get the press that mode leaves spare.
    /// It is exactly where the clip archive already was — see `TalkGesture`.
    ///
    /// This is the test that found `.gesture(held)` swallowing that tap, so it is also the one
    /// that would notice it coming back.
    func testTheMarksOtherPressReachesPhotos() throws {
        let app = try launch()
        let firstSession = app.descendants(matching: .any).matching(identifier: "session-row").firstMatch
        XCTAssertTrue(firstSession.waitForExistence(timeout: 20), "the deck stayed empty")
        firstSession.tap()

        let talk = app.descendants(matching: .any).matching(identifier: "talk-mark").firstMatch
        XCTAssertTrue(talk.waitForExistence(timeout: 15), "the talk button never appeared")
        talk.tap()

        for word in ["Photos", "Clipboard", "Clips"] {
            XCTAssertTrue(app.buttons[word].waitForExistence(timeout: 5), "no \(word) in the menu")
        }
        add(screenshot(app, named: "reach-menu"))

        app.buttons["Photos"].tap()
        // The picker is another process drawn into this one, so nothing here is a Deckhand view.
        // Its Cancel is the one control it is guaranteed to put up whatever the library holds —
        // an empty simulator library included, which is what would make a photo-shaped assertion
        // fail for the wrong reason.
        let picker = app.buttons["Cancel"]
        let opened = picker.waitForExistence(timeout: 10)
        add(screenshot(app, named: "photo-picker"))
        XCTAssertTrue(opened, "Photos opened nothing — the picker needs a host of its own")
    }

    /// The same menu from the other mode, where it is a long press rather than a tap.
    ///
    /// Both are here because the difference between them is what found the bug: the menu worked
    /// in tap-to-talk and did nothing at all in hold-to-talk, which is what narrowed a whole
    /// screen's worth of suspects down to one gesture.
    func testTapToTalkReachesTheMenuByHolding() throws {
        let app = try launch(mode: "toggle")
        let firstSession = app.descendants(matching: .any).matching(identifier: "session-row").firstMatch
        XCTAssertTrue(firstSession.waitForExistence(timeout: 20), "the deck stayed empty")
        firstSession.tap()
        let talk = app.descendants(matching: .any).matching(identifier: "talk-mark").firstMatch
        XCTAssertTrue(talk.waitForExistence(timeout: 15), "the talk button never appeared")

        talk.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Photos"].waitForExistence(timeout: 6), "no menu on a hold")
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

    /// `mode` is nil for whatever the app is set to, which is hold-to-talk out of the box. Named
    /// explicitly by the one test that needs the other, because which press means what is the
    /// entire difference between the two.
    private func launch(mode: String? = nil) throws -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        let token = try XCTUnwrap(env["DECKHAND_TOKEN"], "run via `just ui-test`")
        let app = XCUIApplication()
        app.launchArguments = [
            "-deckhand.host", env["DECKHAND_HOST"] ?? "127.0.0.1:4180",
            "-deckhand.token", token,
            "-deckhand.favorites", "<array/>"
        ]
        if let mode { app.launchArguments += ["-deckhand.talkMode", mode] }
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
