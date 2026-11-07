import XCTest

/// Design review capture of the Home page (Arabic, dark, real data). Screenshots only; asserts nothing about design.
final class HomeReviewUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }
    var n = 0
    func shot(_ name: String) {
        n += 1
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: String(format: "/tmp/review-home-%02d-%@.png", n, name)))
    }
    func back(_ app: XCUIApplication) {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if app.navigationBars.count > 0, b.exists, b.isHittable { b.tap() } else { app.swipeDown(velocity: .fast) }
        sleep(2)
    }
    func testCaptureHome() {
        let app = XCUIApplication.fotiq(); app.launchArguments = ["-lang", "ar"]; app.launch()
        XCTAssertTrue(app.navigationBars["FOTIQ"].waitForExistence(timeout: 30))
        sleep(12)
        shot("top")
        // full page top -> bottom, ~one screen per step
        // Stops as soon as the bottom ("كل الدوريات") is fully on screen, so no duplicate shots.
        let win = app.windows.firstMatch
        let allLeagues = app.buttons["كل الدوريات"].firstMatch
        var prevY: CGFloat = -1
        for step in 1...12 {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: String(format: "/tmp/review-home-full-%02d.png", step)))
            if allLeagues.exists && allLeagues.frame.maxY < win.frame.maxY - 110 && allLeagues.frame.minY > 60 { print("HOME_FULL bottom at step \(step)"); break }
            if allLeagues.exists && abs(allLeagues.frame.minY - prevY) < 2 { print("HOME_FULL no movement at step \(step)"); break }
            prevY = allLeagues.exists ? allLeagues.frame.minY : -1
            win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 0.1, thenDragTo: win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
            sleep(3)
        }
        // back to top
        for _ in 0..<14 { app.swipeDown(velocity: .fast) }
        sleep(2)
        // carousel cards: swipe horizontally on the hero
        let hero = app.scrollViews.firstMatch
        for c in 2...5 {
            let start = hero.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.22))
            let end = hero.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.22))
            start.press(forDuration: 0.05, thenDragTo: end); sleep(2)
            shot("carousel\(c)")
        }
        // toolbar buttons
        let bar = app.navigationBars["FOTIQ"]
        let count = bar.buttons.count
        for i in 0..<count {
            let b = bar.buttons.element(boundBy: i)
            guard b.exists, b.isHittable else { continue }
            let label = b.label.replacingOccurrences(of: " ", with: "_")
            b.tap(); sleep(6)
            shot("toolbar\(i)-\(label)")
            back(app)
            if !bar.exists { app.swipeDown(velocity: .fast); sleep(2) }
        }
        // long-press a match row (context menu + quick preview)
        for _ in 0..<3 { app.swipeUp(velocity: .slow) }
        sleep(2)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS ' - ' OR label CONTAINS ':'")).element(boundBy: 2)
        if row.exists, row.isHittable { row.press(forDuration: 1.5); sleep(3); shot("longpress-preview"); app.tap(); sleep(2) }
        // "all leagues" link at the bottom
        for _ in 0..<12 { app.swipeUp(velocity: .fast) }
        let all = app.buttons["كل الدوريات"]
        if all.waitForExistence(timeout: 5) { all.tap(); sleep(6); shot("all-leagues"); back(app) }
        // open first hero card -> match center
        for _ in 0..<14 { app.swipeDown(velocity: .fast) }
        sleep(2)
        hero.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap(); sleep(8); shot("hero-open-match"); back(app)
        print("HOME_REVIEW toolbar buttons=\(count) labels=\((0..<count).map { bar.buttons.element(boundBy: $0).label })")
    }

    // Separate tests keep a failed tab from preventing capture of other requested pages.
    // These run in the existing dedicated review phase, not instead of the full UI suite.
    func captureSupplement(_ name: String, screen: String, id: Int = 0,
                           tab: String? = nil, secondTeam: Bool = false) throws {
        let app = XCUIApplication.fotiq()
        app.launchArguments = ["-lang", "ar", "-screen", screen, "-id", String(id)]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 30))
        // Render Free can cold-start slowly. Preserve errors in evidence rather than fabricating content.
        if let tab {
            let button = app.buttons[tab].firstMatch
            guard button.waitForExistence(timeout: 90) else {
                shot("extra-\(name)-tab-missing")
                XCTFail("Capture tab missing: \(tab)")
                return
            }
            button.tap()
        } else {
            sleep(15)
        }
        sleep(5)
        if secondTeam {
            let team = app.segmentedControls.firstMatch.buttons.element(boundBy: 1)
            guard team.waitForExistence(timeout: 30) else {
                shot("extra-\(name)-team-missing")
                XCTFail("Second lineup team unavailable")
                return
            }
            team.tap(); sleep(2)
        }
        let win = app.windows.firstMatch
        var previous = ""
        var stable = 0
        var bottom = false
        for page in 1...24 {
            let data = XCUIScreen.main.screenshot().pngRepresentation
            let file = String(format: "/tmp/review-home-extra-%@-%02d.png", name, page)
            try data.write(to: URL(fileURLWithPath: file))
            // Visible text positions remain unchanged after scrolling at the bottom.
            // Two stable passes reduce false stops during delayed lazy layout.
            let signature = app.staticTexts.allElementsBoundByIndex.compactMap { element -> String? in
                let f = element.frame
                guard f.intersects(win.frame), !f.isEmpty else { return nil }
                return "\(element.label):\(Int(f.minY.rounded()))"
            }.joined(separator: "|")
            stable = !signature.isEmpty && signature == previous ? stable + 1 : 0
            if stable >= 2 { bottom = true; break }
            previous = signature
            win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
                .press(forDuration: 0.1, thenDragTo: win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
            sleep(2)
        }
        let status = bottom ? "scroll-stable; inspect images for content/errors" : "capture-limit-reached; coverage incomplete"
        try status.write(toFile: "/tmp/review-home-extra-\(name)-coverage.txt", atomically: true, encoding: .utf8)
        print("HOME_REVIEW supplemental \(name): \(status)")
    }

    func testCaptureMatchLineupsHome() throws { try captureSupplement("lineups-home", screen: "match", id: 1575218, tab: "التشكيلة") }
    func testCaptureMatchLineupsAway() throws { try captureSupplement("lineups-away", screen: "match", id: 1575218, tab: "التشكيلة", secondTeam: true) }
    func testCaptureMatchStatistics() throws { try captureSupplement("statistics", screen: "match", id: 1575218, tab: "الإحصائيات") }
    func testCaptureLeagueScorers() throws { try captureSupplement("scorers", screen: "league", id: 39, tab: "الهدافون") }
    func testCaptureLeagueAssists() throws { try captureSupplement("assists", screen: "league", id: 39, tab: "صناع الأهداف") }
    func testCaptureFullClub() throws { try captureSupplement("club", screen: "club", id: 40) }
    func testCaptureFullPlayer() throws { try captureSupplement("player", screen: "player", id: 1100) }
    func testCaptureFullSettings() throws { try captureSupplement("settings", screen: "settings") }
    func testCaptureCurrentAnalyst() throws { try captureSupplement("analyst", screen: "ai") }

}
