//
//  FavoritesUITests.swift
//  Hybrid AIthleticsUITests
//
//  Functional UI tests for favorite workouts: quick-recording from a Home
//  chip, managing favorites from the card's Edit button, and starting a quick
//  add from the in-sheet "Start from Favorite" menu.
//
//  These tests launch with `-uiTestSeed`, which seeds a single favorite —
//  "Test Favorite Run" (Tempo Run, 4 mi, 32:00) — see `UITestFixtures.swift`.
//

import XCTest

final class FavoritesUITests: XCTestCase {

    /// Name of the favorite seeded by `UITestFixtures.seedFavorites`.
    private let seededFavorite = "Test Favorite Run"

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    /// Launches the app with the UI test seed. Home is the first tab.
    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeed")
        app.launch()
        return app
    }

    /// Returns a Home element, scrolling down once if it starts off-screen
    /// (the favorites card sits below today's training and Quick Record).
    @MainActor
    private func homeElement(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        if !element.waitForExistence(timeout: 3) || !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(element) should exist on Home")
        return element
    }

    /// Asserts the record form shows the seeded favorite's name and distance.
    @MainActor
    private func assertRecordFormShowsSeededFavorite(in app: XCUIApplication) {
        let nameField = app.textFields["workoutForm.nameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "record form should appear")
        XCTAssertEqual(nameField.value as? String, seededFavorite)
        XCTAssertEqual(app.textFields["workoutForm.distanceField"].value as? String, "4.0")
    }

    // MARK: - Tests

    @MainActor
    func testFavoriteChipQuickRecordsForToday() {
        let app = launchApp()

        homeElement(app.buttons["home.favorites.chip.\(seededFavorite)"], in: app).tap()
        assertRecordFormShowsSeededFavorite(in: app)

        app.navigationBars["Record Workout"].buttons["Save"].tap()

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(
            app.staticTexts[seededFavorite].waitForExistence(timeout: 5),
            "the recorded favorite should appear in History"
        )
    }

    @MainActor
    func testEditAddsFavoriteThatAppearsAsChip() {
        let app = launchApp()

        homeElement(app.buttons["home.favorites.edit"], in: app).tap()
        XCTAssertTrue(
            app.buttons["manageFavorites.row.\(seededFavorite)"].waitForExistence(timeout: 5),
            "the seeded favorite should be listed"
        )

        app.buttons["manageFavorites.add"].tap()
        let nameField = app.textFields["favoriteForm.nameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "favorite form should appear")
        nameField.tap()
        // The name starts as the type's default; clear it before typing.
        let current = nameField.value as? String ?? ""
        nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        nameField.typeText("Pool Swim")
        app.buttons["favoriteForm.saveButton"].tap()

        XCTAssertTrue(
            app.buttons["manageFavorites.row.Pool Swim"].waitForExistence(timeout: 5),
            "the new favorite should be listed"
        )
        app.buttons["manageFavorites.done"].tap()

        XCTAssertTrue(
            app.buttons["home.favorites.chip.Pool Swim"].waitForExistence(timeout: 5),
            "the new favorite should appear as a chip"
        )
    }

    @MainActor
    func testQuickAddStartsFromFavoriteMenu() {
        let app = launchApp()

        homeElement(app.buttons["home.logWorkout"], in: app).tap()
        let menu = app.buttons["favoriteMenu.button"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "favorite menu should head a quick add")
        menu.tap()

        let item = app.buttons["favoriteMenu.item.\(seededFavorite)"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "seeded favorite should be in the menu")
        item.tap()

        assertRecordFormShowsSeededFavorite(in: app)
    }
}
