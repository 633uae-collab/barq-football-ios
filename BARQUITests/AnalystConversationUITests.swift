import XCTest

final class AnalystConversationUITests: XCTestCase {
    func testLiveWelcomeRemainsOutsideTheConversation() throws {
        let app = XCUIApplication.fotiq()
        app.launchArguments = ["-lang", "ar", "-startTab", "ai"]
        app.launch()
        XCTAssertTrue(app.buttons["analyst-new-chat"].waitForExistence(timeout: 40))
        app.buttons["analyst-new-chat"].tap()
        let welcome = app.staticTexts["analyst-welcome"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 10))
        // Allow the real Render/Groq request to complete; generic fallback is valid
        // when the provider is unavailable. The saved label records what happened.
        sleep(25)
        XCTAssertTrue(welcome.exists)
        XCTAssertFalse(app.staticTexts["analyst-answer"].exists)
        XCTAssertFalse(app.staticTexts["analyst-error"].exists)
        XCTAssertFalse(app.buttons["analyst-send"].isEnabled)
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        let directory = URL(fileURLWithPath: "/tmp/fotiq-conversation-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try welcome.label.write(to: directory.appendingPathComponent("welcome-observed.txt"), atomically: true, encoding: .utf8)
        try app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("05-live-welcome.png"))
    }

    func testRealBilingualFollowUpsAndConversationRestoration() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchEnvironment["FOTIQ_UI_TEST"] = "1"
        app.launchArguments = ["-lang", "ar", "-resetOnboarding", "YES"]
        app.launch()
        func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        XCTAssertTrue(element("ob-club-40").waitForExistence(timeout: 40))
        XCTAssertFalse(element("ob-next").isEnabled)
        XCTAssertFalse(element("ob-skip").isEnabled)
        element("ob-club-40").tap()
        XCTAssertTrue(element("ob-next").isEnabled)
        element("ob-next").tap()
        XCTAssertTrue(element("ob-back").waitForExistence(timeout: 10))
        element("ob-skip").tap()
        XCTAssertTrue(element("ob-start").waitForExistence(timeout: 10))
        element("ob-skip").tap()
        XCTAssertTrue(element("home-notifications").waitForExistence(timeout: 30))
        let analystTab = app.tabBars.buttons["المحلل"]
        XCTAssertTrue(analystTab.waitForExistence(timeout: 10)); analystTab.tap()
        // Reopening later must use saved onboarding, not a test bypass/reset.
        app.launchArguments = ["-lang", "ar", "-startTab", "ai"]
        let newChat = app.buttons["analyst-new-chat"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 40)); newChat.tap()
        let directory = URL(fileURLWithPath: "/tmp/fotiq-conversation-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("00-welcome.png"))
        XCTAssertTrue(app.staticTexts["analyst-welcome"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "analyst-entity-picker").firstMatch.exists)
        try recording("start", phase: "analyst")
        defer { try? recording("stop") }
        var report = ""
        var lastVerifiedReply = ""
        var receivedTurns: [(question: String, answer: String)] = []
        // Five Arabic and five English questions. Preserve provider spacing.
        let questions = [
            "حلل مباراة مباشرة الآن مع توضيح البيانات الناقصة",
            "For the same match, explain the starting lineups and substitutions in English. Use updated data.",
            "قارن بين ريال مدريد وبرشلونة بناءً على بيانات الموسم",
            "متى تأسس نادي برشلونة؟ اذكر تاريخ التأسيس والمصدر الموثّق",
            "Compare Barcelona and Real Madrid in La Liga 2025/26. Keep each team's statistics separate.",
            "قارن برشلونة وريال مدريد في الدوري الإسباني موسم ٢٠٢٥/٢٦، ولا تعرض أرقاماً غير متحققة",
            "Analyze a live match now. Clearly distinguish confirmed data from unavailable statistics.",
            "للمباراة نفسها، وضّح التشكيلة والتبديلات المتحققة فقط",
            "Compare Real Madrid and Barcelona in La Liga 2025/26. State the competition and season.",
            "When was FC Barcelona founded? Give the verified foundation date and source."
        ]
        XCTAssertEqual(questions.count, 10)
        for (index, question) in questions.enumerated() {
            let field = app.textFields["analyst-question"]
            XCTAssertTrue(field.waitForExistence(timeout: 15)); field.tap(); field.typeText(question)
            // Opening the keyboard alone is not successful text entry.
            XCTAssertEqual(field.value as? String, question, "The actual question must be present before sending")
            XCTAssertTrue(app.buttons["analyst-send"].isEnabled, "Verified input must enable Send")
            let began = Date(); app.buttons["analyst-send"].tap()
            XCTAssertFalse(app.staticTexts["analyst-welcome"].exists, "Welcome must disappear immediately after sending")
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "analyst-welcome-logo").firstMatch.exists)
            let answer = app.staticTexts["analyst-answer"], error = app.staticTexts["analyst-error"]
            let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in answer.exists || error.exists }, object: nil)], timeout: 180)
            let elapsed = Date().timeIntervalSince(began)
            let response = answer.exists ? answer.label : error.exists ? error.label : "Timed out"
            report += "\nQuestion \(index + 1) elapsed=\(elapsed) success=\(answer.exists)\n\(question)\n\(response)\n"
            try report.write(to: directory.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
            try app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("0\(index + 1)-conversation.png"))
            XCTAssertEqual(result, .completed); XCTAssertTrue(answer.exists, response); XCTAssertFalse(error.exists, response)
            if answer.exists {
                lastVerifiedReply = response
                receivedTurns.append((question, response))
            }
            if index == 3 || index == 9 {
                let source = element("analyst-source-link")
                XCTAssertTrue(source.waitForExistence(timeout: 10), "Historical answer must expose its real source")
                XCTAssertEqual(source.label, "Wikidata")
                XCTAssertEqual(source.value as? String, "https://www.wikidata.org/wiki/Q7156")
                XCTAssertTrue(response.contains("1899") || response.contains("١٨٩٩"), "Verified foundation year missing")
                report += "Source: \(source.label) \(source.value ?? "missing")\n"
                try report.write(to: directory.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
            }
            if index < questions.count - 1 { sleep(66) }
        }
        XCTAssertEqual(receivedTurns.count, 10, "Every question requires an actual answer before restoration")
        try recording("stop")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["analyst-history"].waitForExistence(timeout: 30))
        try recording("start", phase: "restored")
        app.buttons["analyst-history"].tap()
        let saved = app.buttons.matching(identifier: "analyst-saved-conversation").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10)); saved.tap()
        let restored = app.staticTexts["analyst-answer"], restoredError = app.staticTexts["analyst-error"]
        XCTAssertTrue(restored.waitForExistence(timeout: 10) || restoredError.exists, "Stored response or failure must survive process termination")
        XCTAssertFalse(lastVerifiedReply.isEmpty, "Restoration requires an actual received answer")
        XCTAssertEqual(restored.label, lastVerifiedReply, "Restore the exact received answer after process termination")
        XCTAssertTrue(element("analyst-source-link").waitForExistence(timeout: 10), "Source must survive conversation restoration")
        XCTAssertEqual(element("analyst-source-link").value as? String, "https://www.wikidata.org/wiki/Q7156")
        try app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("06-restored.png"))
        // Verify every saved question and exact received answer, not only the last.
        // Walk backwards because the restored transcript opens at its bottom.
        for (offset, turn) in receivedTurns.reversed().enumerated() {
            let answerText = app.staticTexts.matching(NSPredicate(format: "label == %@", turn.answer)).firstMatch
            let questionText = app.staticTexts.matching(NSPredicate(format: "label == %@", turn.question)).firstMatch
            var scrolls = 0
            while !(answerText.exists && questionText.exists) && scrolls < 12 {
                app.swipeDown()
                scrolls += 1
            }
            XCTAssertTrue(answerText.exists, "Saved answer \(10 - offset) must match the received text")
            XCTAssertTrue(questionText.exists, "Saved question \(10 - offset) must survive termination")
            try app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("restored-turn-\(10 - offset).png"))
        }
        app.buttons["analyst-new-chat"].tap()
        XCTAssertTrue(app.staticTexts["analyst-welcome"].waitForExistence(timeout: 10))
        app.buttons["analyst-history"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "analyst-saved-conversation").firstMatch.waitForExistence(timeout: 10))
    }
    private func recording(_ action: String, phase: String = "") throws {
        let directory = URL(fileURLWithPath: "/tmp/fotiq-core-recording", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("enabled").path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let udid = try XCTUnwrap(ProcessInfo.processInfo.environment["SIMULATOR_UDID"], "Record the actual XCTest simulator")
        let deadline = Date().addingTimeInterval(20)
        let request: [String: Any] = ["id": id, "action": action, "phase": phase, "udid": udid,
                                      "requestedAt": Date().timeIntervalSince1970,
                                      "expiresAt": deadline.timeIntervalSince1970]
        try JSONSerialization.data(withJSONObject: request).write(to: directory.appendingPathComponent("request.json"), options: .atomic)
        while Date() < deadline {
            if let data = try? Data(contentsOf: directory.appendingPathComponent("ack.json")),
               let ack = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               ack["id"] as? String == id {
                guard ack["ok"] as? Bool == true else {
                    throw NSError(domain: "CoreRecording", code: 1, userInfo: [NSLocalizedDescriptionKey: ack["error"] as? String ?? "Recorder failed"])
                }
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        // A timed-out start must not begin recording after XCTest tears down the app.
        try? Data().write(to: directory.appendingPathComponent("cancelled-\(id)"), options: .atomic)
        throw NSError(domain: "CoreRecording", code: 2, userInfo: [NSLocalizedDescriptionKey: "Recorder acknowledgment missing"])
    }

}


