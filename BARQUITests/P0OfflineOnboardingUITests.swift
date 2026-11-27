import XCTest

/// The unavailable endpoint is deliberate: first-run selection must not depend on the live server.
final class P0OfflineOnboardingUITests: XCTestCase {
    func testOfflineFirstLaunchCanFinishAndRetainChosenClub() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FOTIQ_UI_TEST"] = "1"
        app.launchArguments = ["-lang", "ar", "-resetOnboarding", "YES", "-apiOverride", "https://127.0.0.1:9"]
        app.launch()
        func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
        let firstClub = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'ob-club-'" )).firstMatch
        XCTAssertTrue(firstClub.waitForExistence(timeout: 30))
        // Selection moves a tile to the front of the grid. Bind its identity
        // before tapping instead of re-evaluating a positional firstMatch.
        let club = element(firstClub.identifier)
        let clubName = club.label
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: club)], timeout: 10) == .completed)
        club.tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "on"), object: club)], timeout: 10) == .completed,
                      "The same selected club must become on before continuing")
        element("ob-next").tap()
        XCTAssertTrue(element("ob-skip").waitForExistence(timeout: 10))
        element("ob-skip").tap()
        XCTAssertTrue(element("ob-start").waitForExistence(timeout: 10))
        element("ob-start").tap()
        XCTAssertTrue(element("home-notifications").waitForExistence(timeout: 20))
        app.terminate()
        app.launchArguments = ["-lang", "ar", "-apiOverride", "https://127.0.0.1:9", "-startTab", "favorites"]
        app.launch()
        XCTAssertTrue(app.staticTexts[clubName].firstMatch.waitForExistence(timeout: 30))
        XCTAssertFalse(element("ob-title").exists)
    }
}
