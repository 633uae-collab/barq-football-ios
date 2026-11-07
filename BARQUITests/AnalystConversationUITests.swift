import XCTest

final class AnalystConversationUITests: XCTestCase {
    func testRealBilingualFollowUpsAndConversationRestoration() throws {
        continueAfterFailure = true
        let app = XCUIApplication.fotiq()
        app.launchArguments = ["-lang", "ar", "-startTab", "ai"]
        app.launch()
        let newChat = app.buttons["analyst-new-chat"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 40)); newChat.tap()
        let directory = URL(fileURLWithPath: "/tmp/fotiq-conversation-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("00-welcome.png"))
        var report = ""
        let questions = ["حلل مباراة مباشرة الآن مع توضيح البيانات الناقصة", "For the same match, explain the starting lineups and substitutions in English. Use updated data.", "قارن بين ريال مدريد وبرشلونة بناءً على بيانات الموسم"]
        for (index, question) in questions.enumerated() {
            let field = app.descendants(matching: .any).matching(identifier: "analyst-question").firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 15)); field.tap(); field.typeText(question)
            let began = Date(); app.buttons["analyst-send"].tap()
            let answer = app.staticTexts["analyst-answer"], error = app.staticTexts["analyst-error"]
            let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in answer.exists || error.exists }, object: nil)], timeout: 180)
            let elapsed = Date().timeIntervalSince(began)
            let response = answer.exists ? answer.label : error.exists ? error.label : "Timed out"
            report += "\nQuestion \(index + 1) elapsed=\(elapsed) success=\(answer.exists)\n\(question)\n\(response)\n"
            try report.write(to: directory.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
            try app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("0\(index + 1)-conversation.png"))
            XCTAssertEqual(result, .completed); XCTAssertTrue(answer.exists, response); XCTAssertFalse(error.exists, response)
            if index < questions.count - 1 { sleep(66) }
        }
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["analyst-history"].waitForExistence(timeout: 30))
        app.buttons["analyst-history"].tap()
        let saved = app.buttons.matching(identifier: "analyst-saved-conversation").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10)); saved.tap()
        let restored = app.staticTexts["analyst-answer"], restoredError = app.staticTexts["analyst-error"]
        XCTAssertTrue(restored.waitForExistence(timeout: 10) || restoredError.exists, "Stored response or failure must survive process termination")
        try app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("04-restored.png"))
        app.buttons["analyst-new-chat"].tap()
        XCTAssertTrue(app.staticTexts["هلا بك في FOTIQ AI، اسألني عن أي شيء في عالم كرة القدم"].waitForExistence(timeout: 10))
        app.buttons["analyst-history"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "analyst-saved-conversation").firstMatch.waitForExistence(timeout: 10))
    }
}
