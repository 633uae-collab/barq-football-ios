import XCTest
@testable import BARQ
final class AnalystChatTests: XCTestCase {
    func testSourcesSurviveArchiveAndDoNotMisattributeHistoricalFacts() throws {
        let body = #"{"answer":"Founded 1899-11-29","model":"openai/gpt-oss-120b","fetchedAt":1000,"generatedAt":2000,"sources":[{"name":"Wikidata","url":"https://www.wikidata.org/wiki/Q7156","revision":2562671913,"modifiedAt":"2026-10-30T18:43:49Z"}]}"#
        let reply = try JSONDecoder().decode(AnalystReply.self, from: Data(body.utf8))
        let restored = try JSONDecoder().decode(AnalystReply.self, from: JSONEncoder().encode(reply))
        XCTAssertEqual(restored.sourceNames, "Wikidata")
        XCTAssertEqual(restored.sources?.first?.revision, 2562671913)
        XCTAssertEqual(restored.sources?.first?.link?.host, "www.wikidata.org")
        XCTAssertNil(AnalystSource(url: "javascript:alert(1)").link)
        XCTAssertNil(AnalystSource(url: "http://example.org").link)
        let api = try JSONDecoder().decode(AnalystReply.self, from: Data(#"{"answer":"a","model":"openai/gpt-oss-120b","fetchedAt":1,"generatedAt":2,"sources":[{"path":"/fixtures"},{"path":"/players"}]}"#.utf8))
        XCTAssertEqual(api.sourceNames, "API-Football")
        let legacy = try JSONDecoder().decode(AnalystReply.self, from: Data(#"{"answer":"a","model":"openai/gpt-oss-120b","fetchedAt":1,"generatedAt":2}"#.utf8))
        XCTAssertNil(legacy.sourceNames)
    }
    func testWelcomeExpiresToGenericWithoutBecomingAChatTurn() throws {
        let value = try JSONDecoder().decode(AnalystWelcome.self, from: Data(#"{"text":"What about this match?","dynamic":true,"expiresAt":2000}"#.utf8))
        XCTAssertEqual(value.displayText(at: Date(timeIntervalSince1970: 1), english: true), "What about this match?")
        XCTAssertEqual(value.displayText(at: Date(timeIntervalSince1970: 2), english: false), "كل سؤال في بالك عن الكورة، جوابه هني.")
    }
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
    func testUnknownQuotaResetDoesNotInventSixtySeconds() {
        let message = AnalystChatError(code: "PLAN_LIMIT", retryAfter: nil).errorDescription ?? ""
        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(message.contains("60"))
        XCTAssertTrue((AnalystChatError(code: "AI_FREE_QUOTA_REACHED", retryAfter: 123).errorDescription ?? "").contains("123"))
    }
    func testWrongModelAndEmptyAnswersRejected() async {
        for body in [#"{"answer":"","model":"openai/gpt-oss-120b","fetchedAt":1,"generatedAt":2}"#, #"{"answer":"a","model":"other","fetchedAt":1,"generatedAt":2}"#] {
            StubProtocol.mode = .body(body)
            do { _ = try await API(protocolClasses: [StubProtocol.self], fixedBase: "https://stub.local").askAnalyst("Analyze"); XCTFail("Invalid answer accepted") } catch { }
        }
    }
}
