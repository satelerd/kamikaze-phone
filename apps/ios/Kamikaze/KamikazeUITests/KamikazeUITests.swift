//
//  KamikazeUITests.swift
//  KamikazeUITests
//
//  Created by Daniel Sateler on 12-08-26.
//

import XCTest

final class KamikazeUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testOnboardingReachesPlayableShell() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding"]
        app.launch()

        XCTAssertTrue(app.staticTexts["YOUR PHONE\nIS THE BOARD."].waitForExistence(timeout: 3))
        app.buttons["CONTINUE"].tap()
        XCTAssertTrue(app.staticTexts["CHOOSE YOUR\nLEVEL OF CHAOS."].waitForExistence(timeout: 2))
        app.buttons["CONTINUE"].tap()
        XCTAssertTrue(app.staticTexts["ZERO. THROW.\nLAND."].waitForExistence(timeout: 2))
        app.buttons["ENTER KAMIKAZE"].tap()
        // Simulator has no Core Motion stream, so Play may truthfully show a
        // sensor error. This test owns onboarding/navigation, not device motion.
        // Renamed from START SESSION per player feedback (2026-08-16).
        XCTAssertTrue(app.buttons["THROW"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["Live 3D phone pose"].exists)
        // Renamed from ZERO POSE per player feedback (2026-08-15).
        XCTAssertTrue(app.buttons["LEVEL"].exists)
        XCTAssertTrue(app.tabBars.buttons["PRACTICE"].exists)
    }

    @MainActor
    func testPracticeLessonMovesFromLearnToFollowToTry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingComplete", "YES", "-debugInitialTab", "practice"]
        app.launch()

        let firstReadyTrick = app.staticTexts["BACKSIDE 360 SHUVIT"]
        XCTAssertTrue(firstReadyTrick.waitForExistence(timeout: 4))
        firstReadyTrick.tap()

        let learnStep = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "LEARN")
        ).firstMatch
        XCTAssertTrue(learnStep.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["SHOW ME SLOWLY"].exists)
        app.buttons["SHOW ME SLOWLY"].tap()

        XCTAssertTrue(app.staticTexts["FOLLOW — DON'T THROW YET"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["I'VE GOT IT — TRY"].exists)
        app.buttons["I'VE GOT IT — TRY"].tap()

        XCTAssertTrue(app.buttons["START PRACTICE"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["Live 3D phone pose"].exists)
    }
}
