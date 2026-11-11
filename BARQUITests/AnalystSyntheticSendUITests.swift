import XCTest

// Synthetic transport isolation only. This does not count towards live acceptance.
final class AnalystSyntheticSendUITests: XCTestCase {
    func testTenSyntheticSendsAfterThreeLongTurnsAndRelaunch() throws {
        continueAfterFailure = false
        let udid = try XCTUnwrap(ProcessInfo.processInfo.environment["SIMULATOR_UDID"])
        print("FOTIQ_AX_REPLAY actualUDID=\(udid)")
        let app = XCUIApplication.fotiq()
        app.launchArguments = ["-lang", "ar", "-startTab", "ai"]
        app.launch()
        let answer = app.staticTexts["analyst-answer"]
        XCTAssertTrue(answer.waitForExistence(timeout: 40))
        XCTAssertTrue(answer.label.contains("SYNTHETIC AX CONTROL"))
        let questions = [
            "اختبار مصطنع: حلل نتيجة المباراة", "Synthetic test: explain the same result",
            "اختبار مصطنع: قارن الناديين", "Synthetic test: compare the two clubs",
            "اختبار مصطنع: قارن اللاعبين", "Synthetic test: compare the players",
            "اختبار مصطنع: حلل المباراة المنتهية", "Synthetic test: explain the completed match",
            "اختبار مصطنع: اذكر مصادر الأرقام", "Synthetic test: explain the source limitations"
        ]
        let field = app.textFields["analyst-question"]
        var received: [String] = []
        for (index, question) in questions.enumerated() {
            print("FOTIQ_AX_REPLAY question=\(index + 1) stage=input-start utc=\(Date().timeIntervalSince1970)")
            XCTAssertTrue(field.waitForExistence(timeout: 15))
            field.tap(); field.typeText(question)
            XCTAssertEqual(field.value as? String, question)
            let send = app.buttons["analyst-send"]
            XCTAssertTrue(send.isEnabled)
            send.tap()
            let replyReady = NSPredicate { _, _ in
                answer.exists && answer.label.contains("SYNTHETIC SEND CONTROL") && answer.label.contains(question)
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: replyReady, object: answer)], timeout: 45), .completed)
            XCTAssertFalse(app.staticTexts["analyst-error"].exists)
            let text = answer.label
            XCTAssertGreaterThan(text.utf16.count, 3000)
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic diagnostic fixture — not live")).firstMatch.exists)
            received.append(text)
            print("FOTIQ_AX_REPLAY question=\(index + 1) stage=verified utc=\(Date().timeIntervalSince1970)")
        }
        XCTAssertEqual(received.count, 10)
        app.terminate(); app.launch()
        XCTAssertTrue(answer.waitForExistence(timeout: 30))
        XCTAssertEqual(answer.label, try XCTUnwrap(received.last))
        print("FOTIQ_AX_REPLAY stage=complete utc=\(Date().timeIntervalSince1970)")
    }
}
