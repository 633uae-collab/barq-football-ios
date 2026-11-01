import XCTest

/// UI tests against the real backend (API-SPORTS data). They check that screens render real content, not placeholders.
final class FOTIQUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    func launch(_ args: [String]) -> XCUIApplication {
        let a = XCUIApplication(); a.launchArguments = args; a.launch(); return a
    }
    func anyText(_ app: XCUIApplication, containing s: String, timeout: TimeInterval = 40) -> Bool {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", s)).firstMatch.waitForExistence(timeout: timeout)
    }

    func testHomeShowsBrandAndTabBar() {
        let app = launch([])
        XCTAssertTrue(app.navigationBars["FOTIQ"].waitForExistence(timeout: 30) || anyText(app, containing: "FOTIQ"))
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        for t in ["المباريات", "المحلل", "المفضلة"] {
            let b = app.tabBars.buttons[t]; XCTAssertTrue(b.exists, "tab \(t)"); b.tap()
        }
    }
    func testSearchTeamsPlayersLeagues() {
        for (q, expect) in [("liverpool", "Liverpool"), ("haaland", "Haaland"), ("premier", "Premier")] {
            let app = launch(["-screen", "search", "-q", q])
            XCTAssertTrue(anyText(app, containing: expect), "search \(q) -> \(expect)")
            app.terminate()
        }
    }
    func testLeagueStandingsAndScorers() {
        let app = launch(["-screen", "league", "-id", "39"])
        XCTAssertTrue(anyText(app, containing: "Arsenal"))
    }
    func testClubAndPlayerPages() {
        var app = launch(["-screen", "club", "-id", "40"])
        XCTAssertTrue(anyText(app, containing: "Anfield"))
        app.terminate()
        app = launch(["-screen", "player", "-id", "1100"])
        XCTAssertTrue(anyText(app, containing: "Haaland"))
    }
    func testSettingsAndCalendarOpen() {
        var app = launch(["-screen", "settings"])
        XCTAssertTrue(anyText(app, containing: "المظهر", timeout: 15))
        app.terminate()
        app = launch(["-screen", "monthpicker"])
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 15))
    }
}
