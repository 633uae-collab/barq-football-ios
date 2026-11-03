import XCTest

/// UI tests against the real backend (API-SPORTS data). They check that screens render real content, not placeholders.
final class FOTIQUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    func launch(_ args: [String]) -> XCUIApplication {
        let a = XCUIApplication.fotiq(); a.launchArguments = args; a.launch(); return a
    }
    func anyText(_ app: XCUIApplication, containing s: String, timeout: TimeInterval = 40) -> Bool {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", s)).firstMatch.waitForExistence(timeout: timeout)
    }

    func testHomeShowsBrandAndTabBar() {
        let app = launch([])
        XCTAssertTrue(app.navigationBars["FOTIQ"].waitForExistence(timeout: 30) || anyText(app, containing: "FOTIQ"))
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 60))
        for t in ["المباريات", "المحلل", "المفضلة"] {
            let b = app.tabBars.buttons[t]
            XCTAssertTrue(b.waitForExistence(timeout: 60), "tab \(t)")
            let hittable = NSPredicate(format: "exists == true AND hittable == true")
            XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: b)], timeout: 60), .completed, "tab \(t) hittable")
            b.tap()
        }
    }
    /// Real-data waits. The free Pinggy tunnel expires/rotates (~hourly); measured outage = up to 25 s health-check
    /// detection + reconnect + surge config.json redeploy (runs 41408553776 @08:00:45Z and 41416157145 @09:22:48Z failed
    /// exactly inside that window). The app self-heals (API re-resolves config.json, views retry every 5 s), so give it 180 s.
    static let realData: TimeInterval = 180
    func testSearchTeamsPlayersLeagues() {
        for (q, expect) in [("liverpool", "Liverpool"), ("haaland", "Haaland"), ("premier", "Premier")] {
            let app = launch(["-screen", "search", "-q", q])
            XCTAssertTrue(anyText(app, containing: expect, timeout: Self.realData), "search \(q) -> \(expect)")
            app.terminate()
        }
    }
    func testLeagueStandingsAndScorers() {
        let app = launch(["-screen", "league", "-id", "39"])
        XCTAssertTrue(anyText(app, containing: "Arsenal", timeout: Self.realData))
    }
    func testClubAndPlayerPages() {
        var app = launch(["-screen", "club", "-id", "40"])
        XCTAssertTrue(anyText(app, containing: "Anfield", timeout: Self.realData))
        // Screenshot of Liverpool's club page with the venue (Anfield) on screen.
        let anfield = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Anfield")).firstMatch
        for _ in 0..<8 where !(anfield.exists && anfield.isHittable) { app.swipeUp(); sleep(1) }
        sleep(2)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/v7-15-club-liverpool-anfield.png"))
        app.terminate()
        app = launch(["-screen", "player", "-id", "1100"])
        XCTAssertTrue(anyText(app, containing: "Haaland", timeout: Self.realData))
    }
    func testSettingsAndCalendarOpen() {
        var app = launch(["-screen", "settings"])
        XCTAssertTrue(anyText(app, containing: "المظهر", timeout: 15))
        app.terminate()
        app = launch(["-screen", "monthpicker"])
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 15))
    }

    /// Grants notification permission through the real system alert (so CI can test an APNs payload banner),
    /// then captures the home screen page that holds the FOTIQ icon.
    func testZNotificationPermissionAndHomeIcon() {
        let app = launch(["-screen", "settings", "-requestNotifs", "YES"])
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = sb.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "السماح"])).firstMatch
        if allow.waitForExistence(timeout: 15) { allow.tap() }
        app.terminate()
        XCUIDevice.shared.press(.home)
        sleep(2)
        for _ in 0..<4 {
            if sb.icons["FOTIQ"].exists && sb.icons["FOTIQ"].isHittable { break }
            sb.swipeLeft(); sleep(1)
        }
        XCTAssertTrue(sb.icons["FOTIQ"].exists, "FOTIQ icon on home screen")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/fotiq-springboard.png"))
    }
}

/// Persistence across relaunch + notification filters (real app, real backend).
final class FOTIQPersistenceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    func testSettingsPersistAfterRelaunch() {
        var app = XCUIApplication.fotiq(); app.launchArguments = ["-screen", "settings"]; app.launch()
        let density = app.buttons["settings-density"].firstMatch
        XCTAssertTrue(density.waitForExistence(timeout: 20))
        density.tap()
        let all = app.buttons["الكل"].firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 5)); all.tap()
        sleep(1); app.terminate()
        app = XCUIApplication.fotiq(); app.launchArguments = ["-screen", "settings"]; app.launch()
        XCTAssertTrue(app.buttons["settings-density"].firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["settings-density"].firstMatch.label.contains("الكل"), "density not persisted: \(app.buttons["settings-density"].firstMatch.label)")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "v7-settings"; shot.lifetime = .keepAlways; add(shot); try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/\(shot.name ?? "v7-x").png"))
    }
    func order(_ app: XCUIApplication) -> [String] {
        let q = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'reorder-row-'"))
        _ = q.firstMatch.waitForExistence(timeout: 10)
        // One accessibility snapshot instead of one per row (.frame on each element re-snapshots the whole app,
        // ~3.5 s each on the Intel simulator -> "Timed out while evaluating UI query" in run 41680207668).
        guard let root = try? app.snapshot() else { return [] }
        var rows: [(String, CGFloat)] = []
        func walk(_ e: XCUIElementSnapshot) {
            if e.identifier.hasPrefix("reorder-row-") { rows.append((e.identifier, e.frame.minY)) }
            e.children.forEach(walk)
        }
        walk(root)
        var seen = Set<String>()
        return rows.sorted { $0.1 < $1.1 }.map(\.0).filter { seen.insert($0).inserted }
    }
    func testReorderPersistsAndResets() {
        var app = XCUIApplication.fotiq(); app.launch()
        let btn = app.buttons["home-reorder"].firstMatch
        XCTAssertTrue(btn.waitForExistence(timeout: 30)); btn.tap()
        let start = order(app)
        XCTAssertEqual(start.count, 3, "rows: \(start)")
        // Drag the last row's reorder handle to the top (handle sits at the row's trailing/leading edge).
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'reorder-row-'"))
        var seenR = Set<String>()
        let byY = rows.allElementsBoundByIndex.sorted { $0.frame.minY < $1.frame.minY }.filter { seenR.insert($0.identifier).inserted }
        if let last = byY.last, let first = byY.first {
            let win = app.windows.firstMatch.frame
            let handleX = (last.frame.minX - win.minX) > (win.maxX - last.frame.maxX) ? 0.06 : 0.94
            let from = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: handleX, dy: last.frame.midY / win.height))
            let to = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: handleX, dy: (first.frame.minY - 4) / win.height))
            from.press(forDuration: 0.8, thenDragTo: to)
        }
        sleep(1)
        let edited = order(app)
        print("REORDER start=\(start) edited=\(edited)")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "v7-reorder"; shot.lifetime = .keepAlways; add(shot); try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/v7-reorder.png"))
        app.buttons["تم"].firstMatch.tap()
        sleep(1); app.terminate()
        app = XCUIApplication.fotiq(); app.launch()
        XCTAssertTrue(app.buttons["home-reorder"].firstMatch.waitForExistence(timeout: 30)); app.buttons["home-reorder"].firstMatch.tap()
        XCTAssertEqual(order(app), edited, "order not persisted after relaunch")
        app.buttons["reorder-reset"].firstMatch.tap()
        sleep(1)
        XCTAssertEqual(order(app), ["reorder-row-carousel", "reorder-row-stars", "reorder-row-upcoming"])
        app.buttons["تم"].firstMatch.tap()
    }
    func testNotificationFilters() {
        let app = XCUIApplication.fotiq(); app.launchArguments = ["-screen", "notifications"]; app.launch()
        for k in ["ai", "goals", "results", "all"] {
            let chip = app.buttons["notif-filter-\(k)"].firstMatch
            XCTAssertTrue(chip.waitForExistence(timeout: 20), k); chip.tap()
            XCTAssertTrue(chip.isSelected, "\(k) not selected")
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "v7-notifications-\(k)"; shot.lifetime = .keepAlways; add(shot); try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/\(shot.name ?? "v7-x").png"))
        }
    }
}
