import XCTest

final class PremiumExperienceUITests: XCTestCase {
    func testFooterPhysicalPositionsAndMandatoryClubsResume() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FOTIQ_UI_TEST"] = "1"
        let base = ["-lang", "ar", "-apiOverride", "https://127.0.0.1:9"]
        app.launchArguments = base + ["-resetOnboarding", "YES"]
        app.launch()
        func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        XCTAssertTrue(el("ob-skip").waitForExistence(timeout: 30))
        XCTAssertLessThan(el("ob-skip").frame.midX, el("ob-next").frame.midX)
        XCTAssertFalse(el("ob-skip").isEnabled)
        XCTAssertFalse(el("ob-next").isEnabled)
        app.terminate()
        app.launchArguments = base
        app.launch()
        XCTAssertTrue(el("ob-club-40").waitForExistence(timeout: 30))
        XCTAssertFalse(el("ob-back").exists, "Relaunch must not bypass mandatory clubs")
        XCTAssertFalse(el("ob-next").isEnabled)
        el("ob-club-40").tap()
        XCTAssertTrue(el("ob-next").isEnabled)
        el("ob-next").tap()
        XCTAssertTrue(el("ob-back").waitForExistence(timeout: 15))
        XCTAssertLessThan(el("ob-skip").frame.midX, el("ob-next").frame.midX)
        el("ob-skip").tap()
        XCTAssertTrue(el("ob-start").waitForExistence(timeout: 10))
        XCTAssertLessThan(el("ob-skip").frame.midX, el("ob-start").frame.midX)
        let directory = URL(fileURLWithPath: "/tmp/fotiq-launch-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("04-premium-footer.png"))
        el("ob-start").tap()
        XCTAssertTrue(el("home-notifications").waitForExistence(timeout: 20))
        XCTAssertTrue(app.tabBars.firstMatch.exists)
    }

    func testAnalystTabUsesTheAnimatedEmblem() throws {
        continueAfterFailure = false
        let app = XCUIApplication.fotiq()
        app.launchArguments = ["-lang", "ar", "-startTab", "ai", "-apiOverride", "https://127.0.0.1:9"]
        app.launch()

        let analyst = app.tabBars.buttons["المحلل"]
        XCTAssertTrue(analyst.waitForExistence(timeout: 30))
        XCTAssertTrue(analyst.isHittable)

        let directory = URL(fileURLWithPath: "/tmp/fotiq-launch-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let firstTab = analyst.screenshot().pngRepresentation
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("05-analyst-tab-emblem-start.png"))
        sleep(2)
        let secondTab = analyst.screenshot().pngRepresentation
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("06-analyst-tab-emblem-rotated.png"))

        XCTAssertNotEqual(firstTab, secondTab, "The compact analyst emblem must keep rotating in the native tab bar")
        XCTAssertEqual(app.tabBars.buttons.count, 5, "The emblem must not change the approved tab-bar layout")
    }
    func testRealDynamicWelcomeCaptureWithoutSending() throws {
        let app = XCUIApplication.fotiq()
        app.launchArguments = ["-lang", "ar", "-startTab", "ai", "-apiOverride", "https://barq-football-ios.onrender.com"]
        app.launch()
        XCTAssertTrue(app.buttons["analyst-new-chat"].waitForExistence(timeout: 40))
        app.buttons["analyst-new-chat"].tap()
        XCTAssertTrue(app.staticTexts["analyst-welcome"].waitForExistence(timeout: 10))
        sleep(25)
        XCTAssertTrue(app.staticTexts["analyst-welcome"].exists)
        XCTAssertFalse(app.staticTexts["analyst-answer"].exists)
        XCTAssertFalse(app.buttons["analyst-send"].isEnabled)
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        let directory = URL(fileURLWithPath: "/tmp/fotiq-launch-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("07-real-dynamic-welcome.png"))
        try app.staticTexts["analyst-welcome"].label.write(to: directory.appendingPathComponent("welcome-observed.txt"), atomically: true, encoding: .utf8)
    }

}
