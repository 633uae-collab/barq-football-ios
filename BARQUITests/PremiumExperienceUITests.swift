import XCTest

final class PremiumExperienceUITests: XCTestCase {
    func testFooterPhysicalPositionsAndSkippedClubsResume() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FOTIQ_UI_TEST"] = "1"
        let base = ["-lang", "ar", "-apiOverride", "https://127.0.0.1:9"]
        app.launchArguments = base + ["-resetOnboarding", "YES"]
        app.launch()
        func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        XCTAssertTrue(el("ob-skip").waitForExistence(timeout: 30))
        XCTAssertLessThan(el("ob-skip").frame.midX, el("ob-next").frame.midX)
        el("ob-skip").tap()
        app.terminate()
        app.launchArguments = base
        app.launch()
        XCTAssertTrue(el("ob-back").waitForExistence(timeout: 15), "Skipping clubs must resume leagues")
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
}
