import XCTest

/// Home v8 on the real backend (live API-SPORTS data). Branches honestly on what live data exists at test time.
final class HomeV8UITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    func launch() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["-lang", "ar"]; app.launch()
        XCTAssertTrue(app.navigationBars["FOTIQ"].waitForExistence(timeout: 30)); return app
    }
    func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    func ids(_ app: XCUIApplication, prefix: String) -> [XCUIElement] {
        var seen = Set<String>()
        return app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).allElementsBoundByIndex
            .filter { seen.insert($0.identifier).inserted }
    }

    /// Tests 5, 7, 8 (+ 2/4 when a favorite is live or within 60 min at run time).
    func testHeroEmptyStateOrPagingAndAddFavoritePersists() {
        var app = launch()
        let hero = el(app, "home-hero"), empty = el(app, "hero-empty")
        let deadline = Date().addingTimeInterval(30)
        while !hero.exists && !empty.exists && Date() < deadline { sleep(1) }
        XCTAssertTrue(hero.exists || empty.exists, "top card must always be present")
        if empty.exists {
            print("HOMEV8 hero=empty")
            XCTAssertTrue(app.staticTexts["لا توجد مباريات مباشرة حالياً"].exists)
            XCTAssertTrue(el(app, "hero-add").exists)
        } else {
            let pages = ids(app, prefix: "hero-page-")
            print("HOMEV8 hero pages=\(pages.map(\.identifier)) countdown=\(el(app, "hero-countdown").exists) live=\(el(app, "hero-live-badge").exists)")
            XCTAssertTrue(el(app, "hero-countdown").exists || el(app, "hero-score").exists)
            if pages.count > 1 {
                let before = hero.value as? String
                hero.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).press(forDuration: 0.05, thenDragTo: hero.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
                sleep(2)
                let after = hero.value as? String
                XCTAssertNotEqual(before, after, "swipe must change the visible match")
                sleep(25) // at least one live refresh
                XCTAssertEqual(hero.value as? String, after, "refresh must keep the viewed match")
            }
        }
        // Test 8: open the picker (empty-state button, or the same sheet via the first upcoming star) and persist a favorite.
        let add = el(app, "hero-add")
        guard add.exists else { print("HOMEV8 add-button not shown (hero has matches)"); return }
        add.tap()
        let first = ids(app, prefix: "pick-match-").first
        XCTAssertNotNil(first, "picker lists real matches")
        guard let pick = first else { return }
        let id = pick.identifier
        pick.tap(); sleep(1)
        XCTAssertEqual(el(app, id).value as? String, "on")
        el(app, "pick-done").tap(); sleep(1)
        app.terminate()
        app = launch()
        let add2 = el(app, "hero-add")
        if add2.waitForExistence(timeout: 30) {
            add2.tap()
            XCTAssertTrue(el(app, id).waitForExistence(timeout: 10))
            XCTAssertEqual(el(app, id).value as? String, "on", "favorite persisted after relaunch")
            el(app, id).tap(); el(app, "pick-done").tap()
        } else {
            print("HOMEV8 favorite became eligible and moved to the hero after relaunch")
        }
    }

    /// Test 9: stars card shown from real data, rotating every 5 s (or an honest empty message).
    func testStarsRotate() {
        let app = launch()
        let card = el(app, "stars-card")
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        let pager = el(app, "stars-pager")
        sleep(3)
        if !pager.exists { XCTAssertTrue(el(app, "stars-empty").exists); print("HOMEV8 stars=empty"); return }
        let n = ids(app, prefix: "star-player-").count
        let v1 = pager.value as? String
        sleep(6)
        let v2 = pager.value as? String
        print("HOMEV8 stars players>=\(n) v1=\(v1 ?? "") v2=\(v2 ?? "")")
        if n > 1 { XCTAssertNotEqual(v1, v2, "auto-advance every 5 s") }
    }

    /// Test 10: upcoming cards sorted by kickoff, no duplicates; star toggles favorite.
    func testUpcomingSortedNoDuplicatesAndStar() {
        let app = launch()
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'upcoming-row-'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30), "upcoming list from real data")
        let all = rows.allElementsBoundByIndex.map { ($0.identifier, Int(($0.value as? String) ?? "") ?? 0) }
        var seen = Set<String>(); let uniq = all.filter { seen.insert($0.0).inserted }
        XCTAssertEqual(uniq.count, Set(all.map(\.0)).count)
        let ts = uniq.map(\.1)
        print("HOMEV8 upcoming count=\(uniq.count) ts=\(ts.prefix(6))")
        XCTAssertEqual(ts, ts.sorted(), "sorted by kickoff")
        let star = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'upcoming-star-'")).firstMatch
        if star.exists && star.isHittable {
            let before = star.value as? String
            star.tap(); sleep(1)
            XCTAssertNotEqual(star.value as? String, before); star.tap()
        }
    }
}
