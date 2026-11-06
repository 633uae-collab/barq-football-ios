import XCTest

final class LaunchJourneyUITests: XCTestCase {
    func testInterruptedOfflineJourneyResumesAndCompletedLaunchOpensHome() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FOTIQ_UI_TEST"] = "1"
        let offline = ["-lang", "ar", "-apiOverride", "https://127.0.0.1:9"]
        app.launchArguments = offline + ["-resetOnboarding", "YES"]
        app.launch()
        func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
        let club = element("ob-club-40")
        XCTAssertTrue(club.waitForExistence(timeout: 30))
        club.tap()
        element("ob-next").tap()
        XCTAssertTrue(element("ob-skip").waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = offline
        app.launch()
        XCTAssertTrue(element("ob-skip").waitForExistence(timeout: 15))
        element("ob-back").tap()
        XCTAssertTrue(club.waitForExistence(timeout: 10))
        XCTAssertEqual(club.value as? String, "on")
        element("ob-next").tap()
        element("ob-skip").tap()
        XCTAssertTrue(element("ob-start").waitForExistence(timeout: 10))
        element("ob-start").tap()
        XCTAssertTrue(element("home-notifications").waitForExistence(timeout: 20))
        app.terminate()
        app.launch()
        XCTAssertTrue(element("home-notifications").waitForExistence(timeout: 15))
        XCTAssertFalse(element("ob-title").exists)
    }
}
