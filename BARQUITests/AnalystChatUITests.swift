import XCTest

/// Real questions through the native app and deployed backend. No mock answers.
final class AnalystChatUITests: XCTestCase {
    func testSixQuestionsInArabicAndEnglish() throws {
        continueAfterFailure = true
        let questions = [
            ("حلل مباراة مباشرة الآن", "Analyze a live match now"),
            ("لماذا خسر برشلونة آخر مباراة؟ تحقق أولاً من النتيجة", "Why did Barcelona lose their last match? Verify the result first"),
            ("قارن بين ريال مدريد وبرشلونة", "Compare Real Madrid and Barcelona"),
            ("من أفضل لاعب في الدوري الإنجليزي هذا الموسم؟ وضح معيارك", "Who is the best Premier League player this season? Explain your criteria"),
            ("حلل أداء لاعب خلال آخر خمس مباريات", "Analyze a player over the last five matches"),
            ("توقع نتيجة مباراة برشلونة القادمة بناء على الإحصائيات", "Predict Barcelona's next match based on statistics")
        ]
        var report = ""
        for (index, pair) in questions.enumerated() {
            for (language, question) in [("ar", pair.0), ("en", pair.1)] {
                let app = XCUIApplication.fotiq()
                app.launchArguments = ["-lang", language, "-startTab", "ai"]
                app.launch()
                let field = app.descendants(matching: .any).matching(identifier: "analyst-question").firstMatch
                XCTAssertTrue(field.waitForExistence(timeout: 40))
                if index == 4 {
                    app.buttons["analyst-entity-picker"].tap()
                    let search = app.textFields["analyst-entity-search"]
                    XCTAssertTrue(search.waitForExistence(timeout: 10))
                    search.tap(); search.typeText("haaland")
                    app.buttons["analyst-entity-find"].tap()
                    let player = app.buttons["analyst-player-1100"]
                    XCTAssertTrue(player.waitForExistence(timeout: 60))
                    player.tap()
                }
                field.tap(); field.typeText(question)
                let send = app.buttons["analyst-send"]
                if !send.isHittable { app.swipeUp() }
                let started = Date(); send.tap()
                let answer = app.staticTexts["analyst-answer"].firstMatch
                let failure = app.staticTexts["analyst-error"].firstMatch
                let ready = NSPredicate { _, _ in answer.exists || failure.exists }
                let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 180)
                let elapsed = Date().timeIntervalSince(started)
                let text = answer.exists ? answer.label : (failure.exists ? failure.label : "Timed out")
                report += "\n\(index + 1) \(language) \(elapsed)s\n\(question)\n\(text)\n"
                try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/v7-chat-\(index + 1)-\(language).png"))
                XCTAssertEqual(result, .completed)
                XCTAssertTrue(answer.exists, text)
                XCTAssertFalse(failure.exists, text)
                if answer.exists { XCTAssertGreaterThan(answer.label.count, 30) }
                app.terminate()
                // Respect the server's free-plan global spacing; no automatic retry.
                if index != 5 || language != "en" { sleep(66) }
            }
        }
        try report.write(toFile: "/tmp/fotiq-chat-results.txt", atomically: true, encoding: .utf8)
    }
}
