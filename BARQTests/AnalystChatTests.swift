import XCTest
@testable import BARQ
final class AnalystChatTests: XCTestCase {
    func testDecodesChatReply() async throws {
        StubProtocol.mode = .body(#"{"answer":"تحليل حقيقي","model":"openai/gpt-oss-120b","fetchedAt":1000,"generatedAt":2000}"#)
        let api = API(protocolClasses: [StubProtocol.self], fixedBase: "https://stub.local")
        let result = try await api.askAnalyst("حلل", context: AnalystContext(fixtureId: 7))
        XCTAssertEqual(result.answer, "تحليل حقيقي")
        XCTAssertEqual(result.model, "openai/gpt-oss-120b")
    }
    func testQuotaHasActionableMessage() async {
        StubProtocol.mode = .status(429, #"{"error":"AI_FREE_QUOTA_REACHED"}"#)
        let api = API(protocolClasses: [StubProtocol.self], fixedBase: "https://stub.local")
        do { _ = try await api.askAnalyst("Analyze"); XCTFail("Must reject quota") }
        catch { XCTAssertEqual((error as? AnalystChatError)?.code, "AI_FREE_QUOTA_REACHED"); XCTAssertFalse(error.localizedDescription.isEmpty) }
    }
    func testWrongModelAndEmptyAnswersRejected() async {
        for body in [#"{"answer":"","model":"openai/gpt-oss-120b","fetchedAt":1,"generatedAt":2}"#, #"{"answer":"a","model":"other","fetchedAt":1,"generatedAt":2}"#] {
            StubProtocol.mode = .body(body)
            do { _ = try await API(protocolClasses: [StubProtocol.self], fixedBase: "https://stub.local").askAnalyst("Analyze"); XCTFail("Invalid answer accepted") } catch { }
        }
    }
}
