import XCTest

/// Splash + first-launch onboarding against the real backend (API-Football clubs/leagues/cups).
final class OnboardingUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    static let realData: TimeInterval = 180
    func launch(reset: Bool) -> XCUIApplication {
        let a = XCUIApplication(); a.launchEnvironment["FOTIQ_UI_TEST"] = "1"; a.launchArguments = ["-lang", "ar"] + (reset ? ["-resetOnboarding", "YES"] : []); a.launch(); return a
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
        // Splash lasts ~2 s and XCUI launch() waits for idle, so splash frames are captured in testSplashFrames.
        let title = el(app, "ob-title")
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertEqual(title.label, "اختر أنديتك المفضلة")
        XCTAssertEqual(el(app, "ob-progress").label, "1 من 3")
        let next = el(app, "ob-next")
        XCTAssertFalse(next.isEnabled, "club is mandatory")
        let club = first(app, "ob-club-")
        XCTAssertTrue(club.waitForExistence(timeout: Self.realData), "real clubs loaded")
        sleep(6); shot("02-clubs-empty")
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
        shot("03-clubs-selected")
        next.tap()
        XCTAssertTrue(el(app, "ob-progress").waitForExistence(timeout: 5))
        XCTAssertEqual(el(app, "ob-progress").label, "2 من 3")
        XCTAssertEqual(el(app, "ob-title").label, "اختر دورياتك المفضلة")
        XCTAssertTrue(el(app, "ob-skip").exists)
        let league = first(app, "ob-comp-")
        XCTAssertTrue(league.waitForExistence(timeout: Self.realData))
        sleep(4); shot("05-leagues-empty")
        league.tap(); pace(3); sleep(2); shot("06-leagues-selected"); pace(2)
        el(app, "ob-next").tap(); sleep(1)
        XCTAssertEqual(el(app, "ob-progress").label, "3 من 3")
        XCTAssertEqual(el(app, "ob-title").label, "اختر بطولاتك المفضلة")
        let cup = first(app, "ob-comp-")
        XCTAssertTrue(cup.waitForExistence(timeout: Self.realData))
        sleep(4); shot("07-cups-empty")
        cup.tap(); pace(3); sleep(2); shot("08-cups-selected"); pace(2)
        XCTAssertTrue(el(app, "ob-skip").exists)
        el(app, "ob-start").tap()
        XCTAssertTrue(app.navigationBars["FOTIQ"].waitForExistence(timeout: 30), "lands on home")
        sleep(5); shot("09-home-after-onboarding"); pace(8)

        app.terminate()
        app = launch(reset: false)
        XCTAssertTrue(app.navigationBars["FOTIQ"].waitForExistence(timeout: 30))
        XCTAssertFalse(el(app, "ob-title").exists, "onboarding only once")
        sleep(3); shot("11-relaunch-home"); pace(5)
        app.tabBars.buttons["المفضلة"].tap()
        XCTAssertTrue(app.staticTexts[clubName].waitForExistence(timeout: 15), "chosen club persisted in favorites: \(clubName)")
        shot("12-favorites-after-relaunch"); pace(4)
    }

    func testSkipPathsAndClubSearch() {
        let app = launch(reset: true)
        let search = el(app, "ob-search")
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap(); search.typeText("liverpool")
        let lfc = el(app, "ob-club-40")
        XCTAssertTrue(lfc.waitForExistence(timeout: Self.realData), "real API team search finds Liverpool (40)")
        sleep(3); shot("04-clubs-search")
        lfc.tap(); XCTAssertEqual(lfc.value as? String, "on")
        el(app, "ob-next").tap()
        XCTAssertTrue(el(app, "ob-skip").waitForExistence(timeout: 5)); el(app, "ob-skip").tap(); sleep(1)
        XCTAssertEqual(el(app, "ob-progress").label, "3 من 3")
        el(app, "ob-skip").tap()
        XCTAssertTrue(app.navigationBars["FOTIQ"].waitForExistence(timeout: 30))
        app.tabBars.buttons["المفضلة"].tap()
        XCTAssertTrue(app.staticTexts["Liverpool"].waitForExistence(timeout: 15))
    }

    /// Real frames of the splash animation (held via -splashHold): small logo at start, then mid-zoom.
    func testSplashFrames() {
        for (hold, name) in [("start", "00-splash-start"), ("zoom", "01-splash-zoom"), ("reveal", "01b-splash-reveal")] {
            let a = XCUIApplication(); a.launchEnvironment["FOTIQ_UI_TEST"] = "1"; a.launchArguments = ["-lang", "ar", "-splashHold", hold]; a.launch()
            XCTAssertTrue(a.descendants(matching: .any)["splash"].firstMatch.waitForExistence(timeout: 15), "splash shown")
            sleep(2); shot(name); a.terminate()
        }
        // relaunch splash (onboarding already done in this state or not, splash always on top)
        let a = XCUIApplication.fotiq(); a.launchArguments = ["-lang", "ar", "-splashHold", "zoom"]; a.launch()
        XCTAssertTrue(a.descendants(matching: .any)["splash"].firstMatch.waitForExistence(timeout: 15))
        sleep(1); shot("10-relaunch-splash"); a.terminate()
    }

    /// Splash recording only (splash-video workflow): first launch -> clubs page, relaunch -> home, at normal speed.
    func testSplashRecording() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SPLASH_REC"] == "1", "recording workflow only")
        var a = launch(reset: true)
        XCTAssertTrue(el(a, "ob-title").waitForExistence(timeout: 30)); sleep(5)
        // finish onboarding (1 real club, skip the optional steps) so the relaunch goes splash -> home
        let club = first(a, "ob-club-"); XCTAssertTrue(club.waitForExistence(timeout: Self.realData)); club.tap(); sleep(1)
        el(a, "ob-next").tap(); sleep(1); el(a, "ob-skip").tap(); sleep(1); el(a, "ob-skip").tap()
        XCTAssertTrue(a.navigationBars["FOTIQ"].waitForExistence(timeout: 30)); sleep(2)
        a.terminate(); sleep(2)
        a = launch(reset: false)
        XCTAssertTrue(a.navigationBars["FOTIQ"].waitForExistence(timeout: 30)); sleep(5)
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
