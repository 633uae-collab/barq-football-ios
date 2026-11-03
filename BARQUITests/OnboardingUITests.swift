import XCTest

/// Splash + first-launch onboarding against the real backend (API-Football clubs/leagues/cups).
final class OnboardingUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    static let realData: TimeInterval = 180
    func launch(reset: Bool) -> XCUIApplication {
        let a = XCUIApplication(); a.launchArguments = ["-lang", "ar"] + (reset ? ["-resetOnboarding", "YES"] : []); a.launch(); return a
    }
    func el(_ a: XCUIApplication, _ id: String) -> XCUIElement { a.descendants(matching: .any)[id].firstMatch }
    func first(_ a: XCUIApplication, _ p: String) -> XCUIElement {
        a.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", p)).firstMatch
    }
    /// Extra viewing time only in the onboarding-video workflow (TEST_RUNNER_OB_PACE=1).
    func pace(_ s: UInt32) { if ProcessInfo.processInfo.environment["OB_PACE"] == "1" { sleep(s) } }
    func shot(_ n: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/onb-\(n).png")) }

    func testFirstLaunchFlowSavesAndRelaunchSkipsOnboarding() {
        var app = launch(reset: true)
        XCTAssertTrue(el(app, "splash").waitForExistence(timeout: 10), "splash on launch")
        shot("00-splash")
        let title = el(app, "ob-title")
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertEqual(title.label, "اختر أنديتك المفضلة")
        XCTAssertEqual(el(app, "ob-progress").label, "1 من 3")
        let next = el(app, "ob-next")
        XCTAssertFalse(next.isEnabled, "club is mandatory")
        let club = first(app, "ob-club-")
        XCTAssertTrue(club.waitForExistence(timeout: Self.realData), "real clubs loaded")
        sleep(3); shot("01-clubs")
        pace(3)
        let clubName = club.label
        club.tap(); sleep(1)
        if ProcessInfo.processInfo.environment["OB_PACE"] == "1" {
            let all = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'ob-club-'"))
            for i in [2, 4] where all.count > i { all.element(boundBy: i).tap(); sleep(2) }
            app.swipeUp(velocity: .slow); sleep(2); app.swipeDown(velocity: .slow); sleep(2)
        }
        XCTAssertEqual(club.value as? String, "on")
        XCTAssertTrue(next.isEnabled)
        shot("02-clubs-selected")
        next.tap()
        XCTAssertTrue(el(app, "ob-progress").waitForExistence(timeout: 5))
        XCTAssertEqual(el(app, "ob-progress").label, "2 من 3")
        XCTAssertEqual(el(app, "ob-title").label, "اختر دورياتك المفضلة")
        XCTAssertTrue(el(app, "ob-skip").exists)
        let league = first(app, "ob-comp-")
        XCTAssertTrue(league.waitForExistence(timeout: Self.realData))
        league.tap(); pace(3); sleep(2); shot("03-leagues"); pace(2)
        el(app, "ob-next").tap(); sleep(1)
        XCTAssertEqual(el(app, "ob-progress").label, "3 من 3")
        XCTAssertEqual(el(app, "ob-title").label, "اختر بطولاتك المفضلة")
        let cup = first(app, "ob-comp-")
        XCTAssertTrue(cup.waitForExistence(timeout: Self.realData))
        cup.tap(); pace(3); sleep(2); shot("04-cups"); pace(2)
        XCTAssertTrue(el(app, "ob-skip").exists)
        el(app, "ob-start").tap()
        XCTAssertTrue(app.navigationBars["FOTIQ"].waitForExistence(timeout: 30), "lands on home")
        sleep(5); shot("05-home"); pace(8)

        app.terminate()
        app = launch(reset: false)
        XCTAssertTrue(el(app, "splash").waitForExistence(timeout: 10), "splash every launch")
        shot("07-relaunch-splash")
        XCTAssertTrue(app.navigationBars["FOTIQ"].waitForExistence(timeout: 30))
        XCTAssertFalse(el(app, "ob-title").exists, "onboarding only once")
        sleep(3); shot("08-relaunch-home"); pace(5)
        app.tabBars.buttons["المفضلة"].tap()
        XCTAssertTrue(app.staticTexts[clubName].waitForExistence(timeout: 15), "chosen club persisted in favorites: \(clubName)")
        shot("06-favorites-after-relaunch"); pace(4)
    }

    func testSkipPathsAndClubSearch() {
        let app = launch(reset: true)
        let search = el(app, "ob-search")
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap(); search.typeText("liverpool")
        let lfc = el(app, "ob-club-40")
        XCTAssertTrue(lfc.waitForExistence(timeout: Self.realData), "real API team search finds Liverpool (40)")
        lfc.tap(); XCTAssertEqual(lfc.value as? String, "on")
        el(app, "ob-next").tap()
        XCTAssertTrue(el(app, "ob-skip").waitForExistence(timeout: 5)); el(app, "ob-skip").tap(); sleep(1)
        XCTAssertEqual(el(app, "ob-progress").label, "3 من 3")
        el(app, "ob-skip").tap()
        XCTAssertTrue(app.navigationBars["FOTIQ"].waitForExistence(timeout: 30))
        app.tabBars.buttons["المفضلة"].tap()
        XCTAssertTrue(app.staticTexts["Liverpool"].waitForExistence(timeout: 15))
    }

    func testFavoritesEditableFromSettings() {
        let app = XCUIApplication.fotiq(); app.launchArguments = ["-lang", "ar"]; app.launch()
        XCTAssertTrue(app.navigationBars["FOTIQ"].waitForExistence(timeout: 30))
        el(app, "home-settings").tap()
        let b = el(app, "settings-edit-favorites")
        XCTAssertTrue(b.waitForExistence(timeout: 10)); b.tap()
        XCTAssertTrue(el(app, "ob-title").waitForExistence(timeout: 10))
        XCTAssertEqual(el(app, "ob-progress").label, "1 من 3")
    }
}
