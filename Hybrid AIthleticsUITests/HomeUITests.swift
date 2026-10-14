//
//  HomeUITests.swift
//  Hybrid AIthleticsUITests
//
//  Functional UI tests for the Home tab: today's training, quick record, and
//  the coach conversation.
//
//  These tests launch with `-uiTestSeed`, which forces an in-memory container
//  (no CloudKit), seeds deterministic fixtures (see `UITestFixtures.swift`),
//  and injects `StubAICoachService` so the chat never downloads a real model.
//  The stub's trigger phrases drive each branch: "record" yields a workout
//  proposal, "change my plan" a schedule-change proposal, "garble" a rejected
//  tool call.
//

import XCTest

final class HomeUITests: XCTestCase {

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    /// Launches the app with the UI test seed. Home is the first tab, so it is
    /// already showing.
    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeed")
        app.launch()
        return app
    }

    /// Opens the coach conversation from the Home entry card.
    @MainActor
    private func openChat(in app: XCUIApplication) {
        let card = app.buttons["home.coachCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "coach card should exist")
        card.tap()
        XCTAssertTrue(
            app.textFields["coach.chat.input"].waitForExistence(timeout: 5),
            "composer should appear"
        )
    }

    /// Sends a message through the composer.
    @MainActor
    private func send(_ text: String, in app: XCUIApplication) {
        let input = app.textFields["coach.chat.input"]
        input.tap()
        input.typeText(text)
        let send = app.buttons["coach.chat.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 2), "send button should exist")
        send.tap()
    }

    // MARK: - Landing

    @MainActor
    func testHomeIsTheLandingTab() throws {
        let app = launchApp()
        XCTAssertTrue(
            app.staticTexts["home.todayHeader"].waitForExistence(timeout: 5),
            "Home should be showing on launch without tapping a tab"
        )
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected, "Home tab should be selected")
    }

    @MainActor
    func testHomeTabCoexistsWithTheOtherThree() throws {
        let app = launchApp()
        let tabs = app.tabBars.buttons
        for label in ["Home", "Training", "Strength", "History"] {
            XCTAssertTrue(
                tabs[label].waitForExistence(timeout: 5),
                "\(label) tab should exist"
            )
        }
    }

    @MainActor
    func testAskCoachToolbarButtonIsGoneFromTraining() throws {
        let app = launchApp()
        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(
            app.staticTexts["Aerobic Training"].waitForExistence(timeout: 5),
            "Training tab should load"
        )
        // The one-shot entry point was retired in favor of the Home chat.
        XCTAssertFalse(
            app.buttons["Ask Coach"].exists,
            "Ask Coach should no longer be on the Training tab"
        )
    }

    // MARK: - Today's training

    @MainActor
    func testTodaysSeededWorkoutAppears() throws {
        let app = launchApp()
        // UITestFixtures seeds "Test Workout 1" dated today.
        XCTAssertTrue(
            app.staticTexts["Test Workout 1"].waitForExistence(timeout: 5),
            "today's seeded workout should appear in the Today section"
        )
    }

    @MainActor
    func testTodaysStrengthLaneAppears() throws {
        let app = launchApp()
        XCTAssertTrue(
            app.buttons["home.strengthRow.Test Lift 1"].waitForExistence(timeout: 5),
            "today's strength lane should appear"
        )
        XCTAssertTrue(app.buttons["home.strengthRow.Test Lift 2"].exists)
    }

    @MainActor
    func testOffloadedLiftIsNotShown() throws {
        let app = launchApp()
        XCTAssertTrue(
            app.buttons["home.strengthRow.Test Lift 1"].waitForExistence(timeout: 5),
            "the lane should render before asserting an absence"
        )
        // Offloaded work is deliberately out of the week's plan.
        XCTAssertFalse(
            app.buttons["home.strengthRow.Test Offloaded Lift"].exists,
            "offloaded lifts should not appear on Home"
        )
    }

    // MARK: - Quick record

    @MainActor
    func testQuickRecordOpensTheWorkoutSheet() throws {
        let app = launchApp()
        let logWorkout = app.buttons["home.logWorkout"]
        XCTAssertTrue(logWorkout.waitForExistence(timeout: 5), "Log Workout should exist")
        logWorkout.tap()

        XCTAssertTrue(
            app.navigationBars["Record Workout"].waitForExistence(timeout: 5),
            "the record sheet should open"
        )
        app.buttons["Cancel"].tap()
    }

    @MainActor
    func testLogLiftAsksWhichWhenTheLaneHasSeveral() throws {
        let app = launchApp()
        let logLift = app.buttons["home.logLift"]
        XCTAssertTrue(logLift.waitForExistence(timeout: 5), "Log Lift should exist")
        logLift.tap()

        // Two lifts are seeded into today's lane, so Home must ask.
        XCTAssertTrue(
            app.buttons["Test Lift 1"].waitForExistence(timeout: 5),
            "the lift picker should list today's lane"
        )
    }

    // MARK: - Coach chat

    @MainActor
    func testChatShowsSuggestedPromptsWhenEmpty() throws {
        let app = launchApp()
        openChat(in: app)
        XCTAssertTrue(
            app.buttons["What should change about my upcoming plan?"].waitForExistence(timeout: 5),
            "the retired sheet's question should survive as a suggestion"
        )
    }

    @MainActor
    func testSendingRendersUserThenCoachBubble() throws {
        let app = launchApp()
        openChat(in: app)
        send("How am I doing?", in: app)

        let userBubble = app.otherElements["coach.chat.bubble.user"]
        XCTAssertTrue(
            userBubble.waitForExistence(timeout: 5),
            "the athlete's message should appear"
        )
        let coachBubble = app.otherElements["coach.chat.bubble.coach"]
        XCTAssertTrue(
            coachBubble.waitForExistence(timeout: 10),
            "the coach's streamed reply should appear"
        )
    }

    @MainActor
    func testSuggestedPromptSendsImmediately() throws {
        let app = launchApp()
        openChat(in: app)
        app.buttons["How did last week go?"].tap()

        XCTAssertTrue(
            app.otherElements["coach.chat.bubble.coach"].waitForExistence(timeout: 10),
            "tapping a suggestion should send it"
        )
    }

    @MainActor
    func testWorkoutProposalRendersAcceptAndDismiss() throws {
        let app = launchApp()
        openChat(in: app)
        // "record" is the stub's record_workout trigger.
        send("Please record my run", in: app)

        XCTAssertTrue(
            app.otherElements["coach.chat.proposal"].waitForExistence(timeout: 10),
            "a workout proposal card should appear"
        )
        XCTAssertTrue(app.buttons["coach.chat.accept"].exists)
        XCTAssertTrue(app.buttons["coach.chat.dismiss"].exists)
    }

    @MainActor
    func testAcceptingAWorkoutProposalOpensTheRecordSheet() throws {
        let app = launchApp()
        openChat(in: app)
        send("Please record my run", in: app)

        let accept = app.buttons["coach.chat.accept"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10), "Accept should appear")
        accept.tap()

        // A proposal is never written straight through — it opens the form.
        XCTAssertTrue(
            app.navigationBars["Record Workout"].waitForExistence(timeout: 5),
            "accepting should open the record sheet for confirmation"
        )
    }

    @MainActor
    func testDismissingAProposalRemovesTheCard() throws {
        let app = launchApp()
        openChat(in: app)
        send("Please record my run", in: app)

        let dismiss = app.buttons["coach.chat.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 10), "Dismiss should appear")
        dismiss.tap()

        XCTAssertFalse(
            app.otherElements["coach.chat.proposal"].exists,
            "the proposal card should be gone"
        )
    }

    @MainActor
    func testScheduleChangeProposalRenders() throws {
        let app = launchApp()
        openChat(in: app)
        // "change my plan" is the stub's suggest_schedule_change trigger.
        send("Can you change my plan?", in: app)

        XCTAssertTrue(
            app.otherElements["coach.chat.proposal"].waitForExistence(timeout: 10),
            "a schedule-change proposal card should appear"
        )
    }

    @MainActor
    func testRejectedToolCallIsSurfaced() throws {
        let app = launchApp()
        openChat(in: app)
        // "garble" is the stub's rejected-tool-call trigger.
        send("Please garble this", in: app)

        let coachBubble = app.otherElements["coach.chat.bubble.coach"]
        XCTAssertTrue(
            coachBubble.waitForExistence(timeout: 10),
            "a rejection should be reported, not swallowed into silence"
        )
    }

    @MainActor
    func testClearEmptiesTheTranscript() throws {
        let app = launchApp()
        openChat(in: app)
        send("How am I doing?", in: app)
        XCTAssertTrue(
            app.otherElements["coach.chat.bubble.coach"].waitForExistence(timeout: 10),
            "wait for the reply before clearing"
        )

        let clear = app.buttons["coach.chat.clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "Clear should appear")
        clear.tap()

        XCTAssertFalse(
            app.otherElements["coach.chat.bubble.user"].exists,
            "the transcript should be empty"
        )
        XCTAssertTrue(
            app.buttons["What should change about my upcoming plan?"].exists,
            "suggestions return on an empty transcript"
        )
    }

    @MainActor
    func testConversationSurvivesLeavingAndReturning() throws {
        let app = launchApp()
        openChat(in: app)
        send("How am I doing?", in: app)
        XCTAssertTrue(
            app.otherElements["coach.chat.bubble.coach"].waitForExistence(timeout: 10),
            "wait for the reply"
        )

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            app.staticTexts["home.todayHeader"].waitForExistence(timeout: 5),
            "should be back on Home"
        )
        openChat(in: app)

        // The store is app-scope, so popping and pushing keeps the transcript.
        XCTAssertTrue(
            app.otherElements["coach.chat.bubble.user"].waitForExistence(timeout: 5),
            "the conversation should still be there"
        )
    }
}
