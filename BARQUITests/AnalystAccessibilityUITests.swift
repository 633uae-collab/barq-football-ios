import XCTest

// Diagnostic replay only: the workflow installs an archived response before launch.
// No Send taps, no live Groq claims, and no video. Live acceptance remains separate.
final class AnalystAccessibilityUITests: XCTestCase {
    func testRecordedTranscriptAllowsTenBilingualDraftsAndRelaunch() throws {
        continueAfterFailure = false
        let udid = try XCTUnwrap(ProcessInfo.processInfo.environment["SIMULATOR_UDID"])
        print("FOTIQ_AX_REPLAY actualUDID=\(udid)")
        try (udid + "\n").write(toFile: "/tmp/fotiq-ax-replay-udid.txt", atomically: true, encoding: .utf8)
        let app = XCUIApplication.fotiq()
        app.launchArguments = ["-lang", "ar", "-startTab", "ai"]
        print("FOTIQ_AX_REPLAY stage=launch utc=\(Date().timeIntervalSince1970)")
        app.launch()
        let answer = app.staticTexts["analyst-answer"]
        XCTAssertTrue(answer.waitForExistence(timeout: 40), "The workflow must seed the recorded transcript")
        let originalAnswer = answer.label
        XCTAssertTrue(originalAnswer.contains("Kings Cup"))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Recorded diagnostic fixture — not live")).firstMatch.exists)
        let questions = [
            "حلل المباراة مع توضيح البيانات الناقصة", "Explain the same match in English.",
            "قارن ريال مدريد وبرشلونة", "Compare Barcelona and Real Madrid.",
            "ما هي التشكيلة المتحققة؟", "Which lineup information is confirmed?",
            "اذكر البطولة والموسم", "State the competition and season.",
            "هل توجد إحصاءات للاعبين؟", "Which player statistics are missing?"
        ]
        let field = app.textFields["analyst-question"]
        for (index, question) in questions.enumerated() {
            print("FOTIQ_AX_REPLAY question=\(index + 1) stage=input-start utc=\(Date().timeIntervalSince1970)")
            XCTAssertTrue(field.waitForExistence(timeout: 15))
            field.tap()
            field.typeText(question)
            XCTAssertEqual(field.value as? String, question)
            XCTAssertTrue(app.buttons["analyst-send"].isEnabled)
            XCTAssertFalse(app.staticTexts["analyst-welcome"].exists)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "analyst-welcome-logo").firstMatch.exists)
            XCTAssertEqual(answer.label, originalAnswer)
            print("FOTIQ_AX_REPLAY question=\(index + 1) stage=verified utc=\(Date().timeIntervalSince1970)")
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: question.count))
            // typeText can return before the last deletion reaches SwiftUI/AX.
            // Run 066 captured "C" 8 ms before the app logged zero characters.
            // Wait for the same empty-field condition within the existing 15 s
            // element budget; do not send another delete or alter the draft.
            let emptyDraft = NSPredicate { _, _ in
                guard let value = field.value as? String else { return false }
                return value.isEmpty || value == field.placeholderValue
            }
            let cleared = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: emptyDraft, object: field)], timeout: 15)
            XCTAssertEqual(cleared, .completed, "Draft must be empty after deletion; AX value: \(String(describing: field.value))")
            XCTAssertFalse(app.buttons["analyst-send"].isEnabled)
        }
        app.terminate()
        app.launch()
        XCTAssertTrue(answer.waitForExistence(timeout: 30))
        XCTAssertEqual(answer.label, originalAnswer)
        print("FOTIQ_AX_REPLAY stage=complete utc=\(Date().timeIntervalSince1970)")
    }
}
