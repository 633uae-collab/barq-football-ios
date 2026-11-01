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
        let app = XCUIApplication(); app.launchArguments = ["-lang", "ar"]; app.launch()
        XCTAssertTrue(app.navigationBars["FOTIQ"].waitForExistence(timeout: 30))
        sleep(12)
        shot("top")
        // scroll top -> bottom
        var last = ""
        for i in 0..<12 {
            app.swipeUp(velocity: .slow); sleep(2)
            let sig = app.staticTexts.allElementsBoundByIndex.prefix(6).map(\.label).joined()
            if sig == last { break }; last = sig
            shot("scroll\(i + 1)")
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
        if row.exists { row.press(forDuration: 1.5); sleep(3); shot("longpress-preview"); app.tap(); sleep(2) }
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
}
