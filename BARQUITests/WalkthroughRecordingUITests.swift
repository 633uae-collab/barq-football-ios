import XCTest

/// Real-time walkthrough of FOTIQ for the screen recording (workflow: walkthrough-video.yml).
/// Tolerant: missing elements are logged (WALK SKIP) and the walk continues; it never fails the recording.
final class WalkthroughRecordingUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }
    var app: XCUIApplication!
    func log(_ s: String) { print("WALK \(s)") }
    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    func first(_ prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }
    func text(_ s: String) -> XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", s)).firstMatch }
    func pause(_ s: UInt32) { sleep(s) }
    func slowUp(_ n: Int) { for _ in 0..<n { app.swipeUp(velocity: .slow); pause(2) } }
    func slowDown(_ n: Int) { for _ in 0..<n { app.swipeDown(velocity: .slow); pause(1) } }
    func back() {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.exists && b.isHittable { b.tap() } else { app.swipeRight() }
        pause(2)
    }
    func tab(_ name: String) -> Bool {
        let b = app.tabBars.buttons[name]
        if b.waitForExistence(timeout: 5) { b.tap(); pause(3); return true }
        log("SKIP tab \(name) not found"); return false
    }
    func relaunch(_ args: [String]) {
        app.terminate(); app = XCUIApplication.fotiq(); app.launchArguments = ["-lang", "ar"] + args; app.launch(); pause(3)
    }

    func testWalkthrough() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["WALKTHROUGH"] == "1", "only in walkthrough-video workflow")
        let t0 = Date()
        app = XCUIApplication.fotiq(); app.launchArguments = ["-lang", "ar"]; app.launch()
        log("1 launch nav=\(app.navigationBars["FOTIQ"].waitForExistence(timeout: 60))")
        let hero = el("home-hero"), empty = el("hero-empty")
        let dl = Date().addingTimeInterval(150)
        while !hero.exists && !empty.exists && Date() < dl { sleep(1) }
        _ = el("upcoming-row-").exists; _ = first("upcoming-row-").waitForExistence(timeout: 120)
        pause(6)

        // 2 home top -> bottom
        slowUp(9); pause(3); log("2 home scrolled to bottom"); slowDown(10); pause(3)

        // 3 favorites card swipes
        if hero.exists {
            for _ in 0..<2 {
                hero.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).press(forDuration: 0.1, thenDragTo: hero.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))); pause(3)
                hero.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).press(forDuration: 0.1, thenDragTo: hero.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))); pause(3)
            }
            log("3 hero swiped pages=\(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'hero-page-'")).count)")
        } else if empty.exists {
            log("3 SKIP hero empty (no favorite live/within 60 min); swiping empty card")
            empty.swipeLeft(); pause(2); empty.swipeRight(); pause(2)
            let add = el("hero-add")
            if add.exists { add.tap(); pause(4); app.swipeUp(velocity: .slow); pause(3); let d = el("pick-done"); if d.exists { d.tap() } else { app.swipeDown() }; pause(3); log("3 opened add-matches picker and closed it") }
        } else { log("3 SKIP hero not present") }

        // 5 stars card, wait for auto-advance
        let stars = el("stars-card")
        for _ in 0..<4 where !(stars.exists && stars.isHittable) { app.swipeUp(velocity: .slow); pause(2) }
        if stars.exists {
            let p = el("stars-pager"); let v1 = p.value as? String; pause(16)
            log("5 stars v1=\(v1 ?? "-") v2=\((p.value as? String) ?? "-") changed=\(v1 != (p.value as? String))")
        } else { log("5 SKIP stars card not found") }

        // 6 star then unstar a match
        let star = first("upcoming-star-")
        for _ in 0..<5 where !(star.exists && star.isHittable) { app.swipeUp(velocity: .slow); pause(2) }
        if star.exists && star.isHittable {
            let b = star.value as? String; star.tap(); pause(4); let m = star.value as? String; star.tap(); pause(4)
            log("6 star \(b ?? "-") -> \(m ?? "-") -> \((star.value as? String) ?? "-")")
        } else { log("6 SKIP no hittable upcoming star") }

        // 4 open a match and its tabs
        let row = first("upcoming-row-")
        if row.exists && row.isHittable {
            row.tap(); pause(8); slowUp(2); slowDown(2)
            for t in ["الأحداث", "التشكيلة", "الإحصائيات"] {
                let b = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", t)).firstMatch
                if b.exists { if b.isHittable { b.tap() } ; pause(6); slowUp(2); slowDown(2); log("4 tab \(t) ok") } else { log("4 SKIP tab \(t)") }
            }
            back(); back()
        } else { log("4 SKIP no match row") }
        app.swipeDown(); slowDown(6)

        // 7 club, player, league via search
        if tab("بحث") || { let s = app.tabBars.buttons.element(boundBy: 4); if s.exists { s.tap(); pause(3); return true }; return false }() {
            let field = app.searchFields.firstMatch
            if field.waitForExistence(timeout: 10) {
                field.tap(); pause(1); field.typeText("liverpool"); pause(2)
                let r = app.staticTexts.matching(NSPredicate(format: "label == 'Liverpool'")).firstMatch
                if r.waitForExistence(timeout: 40) { pause(6); app.swipeUp(velocity: .slow); pause(3); log("8 search liverpool results shown") } else { log("8 SKIP search no result in 40s") }
                let c = app.buttons["Cancel"].exists ? app.buttons["Cancel"] : app.buttons["إلغاء"]
                if c.exists { c.tap() } else { app.typeText("\n") }; pause(2)
            } else { log("8 SKIP no search field") }
        }
        // fallbacks (real screens) in case search taps did not navigate
        do {
            relaunch(["-screen", "club", "-id", "40"]); pause(12); slowUp(3); log("7 club page (direct)")
            relaunch(["-screen", "player", "-id", "1100"]); pause(12); slowUp(2); log("7 player page (direct)")
            relaunch(["-screen", "league", "-id", "39"]); pause(12); slowUp(3); log("7 league page (direct)")
            relaunch([])
        }

        // 8 AI analyst
        if tab("المحلل") { pause(10); slowUp(3); slowDown(2); log("8 AI analyst shown") }
        // 8 settings
        if tab("الرئيسية") {
            let s = el("home-settings")
            if s.waitForExistence(timeout: 10) { s.tap(); pause(5); slowUp(4); slowDown(3); log("8 settings shown"); back() } else { log("8 SKIP settings button") }
        }
        // Leagues list + favorites tab
        _ = tab("المفضلة"); pause(5)
        _ = tab("الرئيسية")
        // pad to >= 5.5 min real time on the home screen (live refreshes visible)
        while Date().timeIntervalSince(t0) < 330 { app.swipeUp(velocity: .slow); pause(6); app.swipeDown(velocity: .slow); pause(6) }
        log("done elapsed=\(Int(Date().timeIntervalSince(t0)))s")
    }
}
