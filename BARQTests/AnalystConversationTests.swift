import XCTest
@testable import BARQ

@MainActor final class AnalystConversationTests: XCTestCase {
    func testRestoredHistoryKeepsNewestCompletePairsWithinServerByteLimit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = AnalystConversations(url: url)
        let id = try XCTUnwrap(archive.selectedID)
        for index in 0..<4 {
            let turn = AnalystTurn(question: String(index) + String(repeating: "界", count: 499))
            archive.append(turn, context: AnalystContext())
            let reply = AnalystReply(answer: String(index) + String(repeating: "界", count: 999),
                                     model: "openai/gpt-oss-120b", fetchedAt: 1, generatedAt: 2)
            archive.finish(conversation: id, turn: turn.id, reply: reply)
        }
        let restored = AnalystConversations(url: url).current
        XCTAssertEqual(restored.turns.count, 4)
        let history = restored.history
        XCTAssertEqual(history.map(\.content), restored.turns.suffix(3).flatMap { [$0.question, $0.answer!.answer] })
        XCTAssertEqual(history.map(\.role), ["user", "assistant", "user", "assistant", "user", "assistant"])
        XCTAssertLessThanOrEqual(try JSONEncoder().encode(history).count, 18_000)
    }

    func testUnreadableArchiveIsNeverOverwrittenByInitializationOrNewMessages() throws {
        // Both truncated JSON and a valid JSON value with an unsupported schema
        // must preserve their original bytes for recovery.
        for original in [Data("[{".utf8), Data(#"{"futureArchiveVersion":2}"#.utf8)] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("conversations.json")
            try original.write(to: url)

            let archive = AnalystConversations(url: url)
            XCTAssertNotNil(archive.storageError, "An unsuccessful load must remain visible")
            XCTAssertEqual(try Data(contentsOf: url), original, "Initialization must not replace unread data")
            let loadError = archive.storageError
            let id = try XCTUnwrap(archive.selectedID)
            let turn = AnalystTurn(question: "A new question")
            archive.append(turn, context: AnalystContext(fixtureId: 123))
            archive.finish(conversation: id, turn: turn.id,
                           reply: AnalystReply(answer: "An in-memory reply", model: "openai/gpt-oss-120b", fetchedAt: 1, generatedAt: 2))
            archive.newConversation()
            archive.save()

            XCTAssertEqual(try Data(contentsOf: url), original, "Later writes must also preserve the unread archive")
            XCTAssertEqual(archive.storageError, loadError, "A memory-only conversation must not claim successful persistence")
            XCTAssertEqual(archive.conversations.first(where: { $0.id == id })?.turns.first?.answer?.answer,
                           "An in-memory reply")
            let reopened = AnalystConversations(url: url)
            XCTAssertNotNil(reopened.storageError)
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    func testProviderQueryAndLicenseSurviveReopeningTheArchive() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let wire = Data("""
            [
              {"name":"API-Football","path":"/fixtures","parameters":{"team":101,"season":2025,"round":"Final"}},
              {"name":"Reference","url":"https://example.org/source","license":"CC0","publishedAt":null},
              {"name":"Dated reference","publishedAt":"2025-01-01"},
              {"name":"Legacy source"}
            ]
            """.utf8)
        let sources = try JSONDecoder().decode([AnalystSource].self, from: wire)
        let archive = AnalystConversations(url: url)
        let turn = AnalystTurn(question: "Synthetic source round trip")
        let reply = AnalystReply(answer: "Example", model: "verified-provider-data",
                                 fetchedAt: 1, generatedAt: 2, sources: sources)
        archive.append(turn, context: AnalystContext())
        archive.finish(conversation: archive.current.id, turn: turn.id, reply: reply)

        let restored = AnalystConversations(url: url)
        let restoredSources = try XCTUnwrap(restored.current.turns.first?.answer?.sources)
        let encoded = try JSONEncoder().encode(restoredSources)
        let originalRows = try XCTUnwrap(JSONSerialization.jsonObject(with: wire) as? NSArray)
        let restoredRows = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? NSArray)
        XCTAssertEqual(restoredRows, originalRows)
    }

    func testEveryReplyKindAndItsSourceSurviveStorage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = AnalystConversations(url: url)
        let id = try XCTUnwrap(archive.selectedID)
        for kind in AnalystResponseKind.allCases {
            let turn = AnalystTurn(question: "Question")
            let reply = AnalystReply(answer: "Exact reply", model: kind.rawValue, fetchedAt: 1, generatedAt: 2,
                                     sources: [AnalystSource(name: "Source", url: "https://example.org/evidence")])
            archive.append(turn, context: AnalystContext())
            archive.finish(conversation: id, turn: turn.id, reply: reply)
        }
        let restored = AnalystConversations(url: url)
        XCTAssertEqual(restored.current.turns.count, AnalystResponseKind.allCases.count)
        for (turn, kind) in zip(restored.current.turns, AnalystResponseKind.allCases) {
            XCTAssertEqual(turn.answer?.answer, "Exact reply")
            XCTAssertEqual(turn.answer?.responseKind, kind)
            XCTAssertEqual(turn.answer?.sources?.first?.link?.absoluteString, "https://example.org/evidence")
        }
        XCTAssertNil(restored.storageError)
    }
    func testLongConversationRestoresWithoutSendingCachedAnswerAndBoundsNetworkHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("conversations.json")
        let archive = AnalystConversations(url: url)
        let id = try XCTUnwrap(archive.selectedID)
        for n in 0..<30 {
            let turn = AnalystTurn(question: "Question \(n)")
            archive.append(turn, context: AnalystContext(fixtureId: 123))
            archive.finish(conversation: id, turn: turn.id, reply: AnalystReply(answer: String(repeating: "answer ", count: 300), model: "openai/gpt-oss-120b", fetchedAt: 1000, generatedAt: 2000))
        }
        XCTAssertEqual(archive.current.history.count, 8)
        XCTAssertTrue(archive.current.history.allSatisfy { $0.content.count <= 1000 })
        archive.newConversation()
        XCTAssertTrue(archive.current.history.isEmpty)
        let restored = AnalystConversations(url: url)
        restored.selectedID = id
        XCTAssertEqual(restored.current.turns.count, 30)
        XCTAssertEqual(restored.current.context.fixtureId, 123)
        XCTAssertNil(restored.storageError)
        XCTAssertEqual(restored.current.turns.first?.question, "Question 0")
    }
    func testArabicDiacriticsAndEmojiRespectServerUTF16LimitWithoutChangingSavedReply() {
        let text = String(repeating: "سُؤال ⚽️ 👨‍👩‍👧‍👦 ", count: 200)
        let turn = AnalystTurn(question: text, answer: AnalystReply(answer: text, model: "openai/gpt-oss-120b", fetchedAt: 1, generatedAt: 2))
        let conversation = AnalystConversation(turns: [turn])
        XCTAssertEqual(conversation.turns.first?.answer?.answer, text)
        XCTAssertEqual(conversation.history.count, 2)
        XCTAssertLessThanOrEqual(conversation.history[0].content.utf16.count, 500)
        XCTAssertLessThanOrEqual(conversation.history[1].content.utf16.count, 1000)
        for message in conversation.history {
            XCTAssertFalse(message.content.isEmpty)
            XCTAssertTrue(text.hasPrefix(message.content))
            XCTAssertFalse(message.content.contains("�"))
        }
    }
    func testInterruptedAndFailedTurnsAreRetainedButNotSentAsAssistantHistory() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = AnalystConversations(url: url)
        let id = try XCTUnwrap(archive.selectedID), turn = AnalystTurn(question: "Analyze")
        archive.append(turn, context: AnalystContext())
        XCTAssertTrue(archive.current.history.isEmpty)
        archive.finish(conversation: id, turn: turn.id, error: "Quota exhausted")
        let restored = AnalystConversations(url: url)
        XCTAssertEqual(restored.current.turns.first?.error, "Quota exhausted")
        XCTAssertTrue(restored.current.history.isEmpty)
    }
}

