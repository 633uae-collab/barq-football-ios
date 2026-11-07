import XCTest
@testable import BARQ

@MainActor final class AnalystConversationTests: XCTestCase {
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
