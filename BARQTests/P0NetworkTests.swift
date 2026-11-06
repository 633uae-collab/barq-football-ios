import XCTest
@testable import BARQ

final class P0Protocol: URLProtocol {
    private static let lock = NSLock()
    private static var replies: [(Int, String, String)] = []
    private static var requests = 0
    static var count: Int { lock.lock(); defer { lock.unlock() }; return requests }
    static func reset(_ values: [(Int, String, String)]) {
        lock.lock(); defer { lock.unlock() }
        replies = values; requests = 0
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests += 1
        let reply = Self.replies.isEmpty ? (500, "application/json", "{}") : Self.replies.removeFirst()
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.0, httpVersion: nil, headerFields: ["Content-Type": reply.1])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.2.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class P0NetworkTests: XCTestCase {
    struct Body: Codable { var ok = true }
    func api() -> API { API(protocolClasses: [P0Protocol.self], fixedBase: "https://stub.local", retryDelay: 0) }

    func testWriteRejectsHTTP200TunnelHTML() async {
        P0Protocol.reset([(200, "text/html", "<html>Site Unavailable</html>")])
        do { try await api().send("PUT", "/api/prefs/device", body: Body()); XCTFail("HTML must not acknowledge a write") }
        catch { XCTAssertNotNil(error as? APIError) }
    }
    func testWriteRejectsServerErrorAndFalseAcknowledgement() async {
        for reply in [(503, "application/json", "{\"error\":\"unavailable\"}"),
                      (401, "application/json", "{\"error\":\"unauthorized\"}"),
                      (200, "application/json", "{\"ok\":false}"),
                      (200, "application/json", "<html>Site Unavailable</html>"),
                      (200, "application/json", "{}"), (200, "application/json", "")] {
            P0Protocol.reset([reply])
            do { try await api().send("PUT", "/api/prefs/device", body: Body()); XCTFail("Unconfirmed write: \(reply)") }
            catch { XCTAssertNotNil(error as? APIError) }
        }
    }
    func testWriteAcceptsExplicitAcknowledgementAndNoContent() async throws {
        for reply in [(200, "application/json", "{\"ok\":true}"), (204, "application/json", "")] {
            P0Protocol.reset([reply]); try await api().send("PUT", "/api/prefs/device", body: Body())
        }
    }
    func testReadRetriesTransientJSONFailureThenSucceeds() async throws {
        P0Protocol.reset([(503, "application/json", "{\"error\":\"temporary\"}"), (200, "application/json", "{\"ok\":true}")])
        let value: Body = try await api().get("/api/check")
        XCTAssertTrue(value.ok); XCTAssertEqual(P0Protocol.count, 2)
    }
    func testReadDoesNotRetryAuthenticationFailure() async {
        P0Protocol.reset([(401, "application/json", "{\"error\":\"unauthorized\"}")])
        do { let _: Body = try await api().get("/api/check"); XCTFail("expected rejection") } catch {}
        XCTAssertEqual(P0Protocol.count, 1)
    }
    func testReadRetryBudgetIsBoundedForTunnelHTML() async {
        P0Protocol.reset(Array(repeating: (200, "text/html", "<html>Site Unavailable</html>"), count: 5))
        do { let _: Body = try await api().get("/api/check", attempts: 2); XCTFail("expected failure") } catch {}
        XCTAssertEqual(P0Protocol.count, 2)
    }
    func testCancellationStopsRetryLoop() async {
        P0Protocol.reset(Array(repeating: (503, "application/json", "{}"), count: 4))
        let api = API(protocolClasses: [P0Protocol.self], fixedBase: "https://stub.local", retryDelay: 10)
        let task = Task { let _: Body = try await api.get("/api/check") }
        for _ in 0..<100 {
            if P0Protocol.count > 0 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(P0Protocol.count, 1)
        task.cancel()
        do { try await task.value; XCTFail("expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(P0Protocol.count, 1)
    }
}
