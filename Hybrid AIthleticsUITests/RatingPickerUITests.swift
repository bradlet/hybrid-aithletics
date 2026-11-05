//
//  RatingPickerUITests.swift
//  Hybrid AIthleticsUITests
//
//  Functional UI tests for the two radial rating dials in the workout form:
//  feeling (1–5) and perceived exertion (1–10).
//
//  These tests launch the app with the `-uiTestSeed` argument, which forces
//  an in-memory model container and seeds 25 deterministic workouts (see
//  `UITestFixtures.swift`). "Test Workout 1" is index 0, so it seeds with
//  feeling 1 ("Very Weak") and exertion 1 ("Very Light").
//
//  Exact-value assertions go through the chevron steppers: XCUI cannot invoke
//  a custom `accessibilityAdjustableAction`, and drag distance is
//  device-metric dependent, so the drag test asserts only that the value moved.
//

import XCTest

final class RatingPickerUITests: XCTestCase {

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    /// Launches the app, opens the first History row's edit sheet, and scrolls
    /// the form down to the two dials (they sit below the notes section).
    @MainActor
    private func launchAndOpenDials() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeed")
        app.launch()

        app.tabBars.buttons["History"].tap()
        let firstRow = app.staticTexts["Test Workout 1"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "seeded row should exist")
        firstRow.tap()
        XCTAssertTrue(
            app.navigationBars["Edit Workout"].waitForExistence(timeout: 3),
            "edit sheet should present"
        )

        scrollToDials(in: app)
        return app
    }

    /// Scrolls the form until the exertion dial is actually *hittable*.
    ///
    /// Waiting on the value labels is not enough: a dial scrolled below the
    /// fold still reports `exists == true` from the accessibility tree, but
    /// its frame sits off-screen and drags against it are dropped.
    @MainActor
    private func scrollToDials(in app: XCUIApplication) {
        let dial = exertionDial(in: app)
        var attempts = 0
        while !dial.isHittable && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(
            app.staticTexts["feelingPicker.valueLabel"].waitForExistence(timeout: 3),
            "feeling dial should be reachable"
        )
        XCTAssertTrue(dial.isHittable, "exertion dial should scroll into view")
    }

    @MainActor
    private func exertionDial(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "exertionPicker.dial").firstMatch
    }

    // MARK: - Tests

    @MainActor
    func testFeelingStepperAdvancesOneDetent() throws {
        let app = launchAndOpenDials()

        let label = app.staticTexts["feelingPicker.valueLabel"]
        XCTAssertEqual(label.label, "Very Weak", "fixture 1 seeds feeling = 1")

        app.buttons["feelingPicker.increment"].tap()
        XCTAssertEqual(label.label, "Weak")

        app.buttons["feelingPicker.increment"].tap()
        XCTAssertEqual(label.label, "Normal")

        app.buttons["feelingPicker.decrement"].tap()
        XCTAssertEqual(label.label, "Weak")
    }

    @MainActor
    func testFeelingStepperClampsAtBothEnds() throws {
        let app = launchAndOpenDials()

        let label = app.staticTexts["feelingPicker.valueLabel"]
        let decrement = app.buttons["feelingPicker.decrement"]

        // Below slot 1 lies the unset slot, and the dial stops there.
        decrement.tap()
        XCTAssertEqual(label.label, "Not set")
        decrement.tap()
        XCTAssertEqual(label.label, "Not set", "dial must not wrap past unset")

        let increment = app.buttons["feelingPicker.increment"]
        for _ in 0..<8 { increment.tap() }
        XCTAssertEqual(label.label, "Very Strong", "dial must not wrap past the top")
    }

    @MainActor
    func testExertionStepperUsesRPEBuckets() throws {
        let app = launchAndOpenDials()

        let label = app.staticTexts["exertionPicker.valueLabel"]
        XCTAssertEqual(label.label, "Very Light", "fixture 1 seeds exertion = 1")

        let increment = app.buttons["exertionPicker.increment"]
        increment.tap()
        XCTAssertEqual(label.label, "Light", "2 is Light")

        for _ in 0..<3 { increment.tap() }
        XCTAssertEqual(label.label, "Hard", "5–6 share the Hard bucket")

        for _ in 0..<5 { increment.tap() }
        XCTAssertEqual(label.label, "Maximum", "10 is its own bucket")
    }

    @MainActor
    func testClearResetsFeelingToNotSet() throws {
        let app = launchAndOpenDials()

        let label = app.staticTexts["feelingPicker.valueLabel"]
        XCTAssertNotEqual(label.label, "Not set")

        app.buttons["feelingPicker.clear"].tap()
        XCTAssertEqual(label.label, "Not set")
        XCTAssertFalse(
            app.buttons["feelingPicker.clear"].exists,
            "Clear should hide once there is nothing to clear"
        )
    }

    @MainActor
    func testRatingSelectionPersistsAcrossSave() throws {
        let app = launchAndOpenDials()

        app.buttons["feelingPicker.increment"].tap()
        app.buttons["exertionPicker.increment"].tap()
        let feelingAfterEdit = app.staticTexts["feelingPicker.valueLabel"].label
        let exertionAfterEdit = app.staticTexts["exertionPicker.valueLabel"].label
        XCTAssertEqual(feelingAfterEdit, "Weak")
        XCTAssertEqual(exertionAfterEdit, "Light")

        app.buttons["workoutDetail.saveButton"].tap()

        // Reopen the same row and confirm the dials parked on the saved values.
        let reopened = app.staticTexts["Test Workout 1"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 3))
        reopened.tap()
        scrollToDials(in: app)
        let label = app.staticTexts["feelingPicker.valueLabel"]
        XCTAssertEqual(label.label, feelingAfterEdit)
        XCTAssertEqual(app.staticTexts["exertionPicker.valueLabel"].label, exertionAfterEdit)
    }

    @MainActor
    func testExertionDialRespondsToDrag() throws {
        let app = launchAndOpenDials()

        let label = app.staticTexts["exertionPicker.valueLabel"]
        let before = label.label

        let dial = exertionDial(in: app)
        XCTAssertTrue(dial.isHittable, "exertion dial should be hittable")

        // Swipe left to bring higher values to 12 o'clock. A slow velocity
        // gives the gesture's direction latch enough events to declare itself
        // horizontal before the finger lifts.
        let start = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(
            forDuration: 0.1,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0.1
        )

        // Only "it moved" — drag distance in points is device-metric dependent,
        // so exact detent counts belong to the stepper tests above.
        XCTAssertNotEqual(label.label, before, "drag should advance the dial")
    }
}
