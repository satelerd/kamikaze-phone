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
        XCTAssertTrue(app.staticTexts["THROW\nSMART."].waitForExistence(timeout: 2))
        app.buttons["CONTINUE"].tap()
        XCTAssertTrue(app.staticTexts["KAMIKAZE\nSTARTED HERE."].waitForExistence(timeout: 2))
        keepScreenshot(of: app, named: "onboarding-2014-origin")
        app.buttons["CONTINUE"].tap()
        XCTAssertTrue(app.staticTexts["THREE MOVES.\nTHAT'S IT."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["PRESS START"].exists)
        XCTAssertTrue(app.staticTexts["THROW + CATCH"].exists)
        XCTAssertTrue(app.staticTexts["HOLD STILL"].exists)
        app.buttons["TRY THE ORIGINAL"].tap()
        XCTAssertTrue(app.staticTexts["THROW YOUR PHONE\n50 CM."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["START"].exists)
        XCTAssertTrue(app.staticTexts["THROW"].exists)
        XCTAssertTrue(app.staticTexts["RESULT"].exists)
        keepScreenshot(of: app, named: "onboarding-straight-air")
        // Simulator has no Core Motion stream, so Play may truthfully show a
        // sensor error. The honest fallback still lets this navigation test
        // inspect the TARGET preview and reach the shell.
        app.buttons["CONTINUE WITHOUT SENSOR"].tap()
        XCTAssertTrue(app.staticTexts["LEARN A\nSHUVIT."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["Replay 3D phone"].exists)
        keepScreenshot(of: app, named: "onboarding-shuvit-preview")
        app.buttons["TRY THE SHUVIT"].tap()
        XCTAssertTrue(app.staticTexts["LAND A SHUVIT."].waitForExistence(timeout: 2))
        app.buttons["CONTINUE WITHOUT SENSOR"].tap()
        XCTAssertTrue(app.staticTexts["NICE. NOW\nLEARN A FLIP."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["Replay 3D phone"].exists)
        app.buttons["TRY THE FLIP"].tap()
        XCTAssertTrue(app.staticTexts["LAND A FLIP."].waitForExistence(timeout: 2))
        app.buttons["CONTINUE WITHOUT SENSOR"].tap()
        // Renamed from START SESSION per player feedback (2026-08-16).
        XCTAssertTrue(app.buttons["THROW"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["Live 3D phone pose"].exists)
        // Renamed from ZERO POSE per player feedback (2026-08-15).
        XCTAssertTrue(app.buttons["LEVEL"].exists)
        XCTAssertTrue(app.tabBars.buttons["PRACTICE"].exists)
    }

    @MainActor
    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testPracticeLessonMovesFromLearnToTryAndBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingComplete", "YES", "-debugInitialTab", "practice"]
        app.launch()

        let firstReadyTrick = app.staticTexts["BACKSIDE SHUVIT"]
        XCTAssertTrue(firstReadyTrick.waitForExistence(timeout: 4))
        firstReadyTrick.tap()

        let learnStep = app.buttons["practice-step-learn"]
        XCTAssertTrue(learnStep.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["TRY THIS TRICK"].exists)
        app.buttons["TRY THIS TRICK"].tap()

        XCTAssertTrue(app.buttons["START PRACTICE"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["Live 3D phone pose"].exists)

        app.buttons["practice-step-learn"].tap()
        XCTAssertTrue(app.staticTexts["WATCH THE TARGET"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["TRY THIS TRICK"].exists)
    }

    @MainActor
    func testProfileLeadsWithTheEquippedPhoneAndNextSkill() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingComplete", "YES", "-debugInitialTab", "profile"]
        app.launch()

        XCTAssertTrue(app.otherElements["Live 3D phone pose"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["SETUP"].exists)
        // The authored ladder now starts with the foundational 180-degree
        // Shuvit pair. The previous expectation skipped directly to the
        // full-rotation variant and no longer matched the player flow.
        XCTAssertTrue(app.staticTexts["BACKSIDE SHUVIT"].exists)
        XCTAssertTrue(app.staticTexts["0/3"].exists)
    }

    /// Physical-device visual gate for Camera V2. The unit suite verifies
    /// the authored -Z face contract; this test keeps a screenshot proving
    /// that the live selfie material is actually visible on that display in
    /// the shipping Play scene. A simulator cannot provide the camera stream.
    @MainActor
    func testPhysicalCameraAppearsOnPhoneDisplay() throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Camera V2 needs a physical iPhone")
#else
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingComplete", "YES", "-debugInitialTab", "play"]

        addUIInterruptionMonitor(withDescription: "Camera permission") { alert in
            let allow = alert.buttons["Allow"]
            if allow.exists {
                allow.tap()
                return true
            }
            return false
        }

        app.launch()
        let cameraOff = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'CAMERA' AND label CONTAINS[c] 'OFF'")
        ).firstMatch
        XCTAssertTrue(cameraOff.waitForExistence(timeout: 6))
        cameraOff.tap()
        app.tap() // Gives an eventual system permission alert to the monitor.

        XCTAssertTrue(app.staticTexts["ON"].waitForExistence(timeout: 8))
        sleep(2)
        keepScreenshot(of: app, named: "camera-v2-phone-display")
#endif
    }
}
