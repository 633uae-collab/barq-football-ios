import XCTest
@testable import BARQ

// Fault injection only. These responses never come from Render or Groq.
private final class AnalystFaultProtocol: URLProtocol {
    enum Fault { case network(URLError.Code), status(Int, String, String?), pending }
    private static let lock = NSLock()
    private static var faults: [String: Fault] = [:]
    private static var counts: [String: Int] = [:]
    static func configure(_ fault: Fault) -> String {
        let host = UUID().uuidString.lowercased() + ".invalid"
        lock.lock(); defer { lock.unlock() }
        faults[host] = fault; counts[host] = 0
        return host
    }
    static func count(_ host: String) -> Int {
        lock.lock(); defer { lock.unlock() }; return counts[host] ?? 0
    }
    private static func started(_ host: String) -> Fault {
        lock.lock(); defer { lock.unlock() }
        counts[host, default: 0] += 1
        return faults[host] ?? .network(.unsupportedURL)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        switch Self.started(request.url!.host!) {
        case .network(let code): client?.urlProtocol(self, didFailWithError: URLError(code))
        case .status(let code, let body, let retryAfter):
            var headers = ["Content-Type": "application/json"]
            headers["Retry-After"] = retryAfter
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .pending: break // Remains pending until the caller cancels; no sleeping UI thread.
        }
    }
    override func stopLoading() {}
}

final class AnalystTransportFaultTests: XCTestCase {
    private func api(_ host: String) -> API {
        API(protocolClasses: [AnalystFaultProtocol.self], fixedBase: "https://" + host)
    }
    func testOfflineTLSAndTimeoutPreserveErrorAndNeverResendPOST() async {
        for code in [URLError.Code.notConnectedToInternet, .secureConnectionFailed, .serverCertificateUntrusted, .timedOut, .networkConnectionLost] {
            let host = AnalystFaultProtocol.configure(.network(code))
            do { _ = try await api(host).askAnalyst("Fault-injection test"); XCTFail("Transport fault must not become an answer") }
            catch {
                XCTAssertEqual((error as NSError).domain, NSURLErrorDomain)
                XCTAssertEqual((error as NSError).code, code.rawValue)
                for english in [true, false] {
                    XCTAssertNotNil(AnalystNetworkFailure.message(for: error, english: english))
                }
            }
            XCTAssertEqual(AnalystFaultProtocol.count(host), 1, "No automatic POST retry may consume another quota slot")
        }
    }
    func test503AndQuotaRejectAnswersAndRetainRetryAfterWithoutRetrying() async {
        for (status, code) in [(503, "AI_UPSTREAM_UNAVAILABLE"), (429, "AI_FREE_QUOTA_REACHED")] {
            let host = AnalystFaultProtocol.configure(.status(status, "{\"error\":\"\(code)\"}", "123"))
            do { _ = try await api(host).askAnalyst("Fault-injection test"); XCTFail("Server failure must not become an answer") }
            catch {
                XCTAssertEqual((error as? AnalystChatError)?.code, code)
                XCTAssertEqual((error as? AnalystChatError)?.retryAfter, 123)
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
            XCTAssertEqual(AnalystFaultProtocol.count(host), 1)
        }
    }
    func testPendingRequestAllowsMainActorProgressAndCanBeCancelled() async {
        let host = AnalystFaultProtocol.configure(.pending)
        let api = api(host)
        let request = Task { try await api.askAnalyst("Simulated slow server") }
        for _ in 0..<100 {
            if AnalystFaultProtocol.count(host) == 1 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(AnalystFaultProtocol.count(host), 1)
        let mainActorProgress = await MainActor.run { true }
        XCTAssertTrue(mainActorProgress)
        request.cancel()
        do { _ = try await request.value; XCTFail("Cancelled request must not return a response") }
        catch { XCTAssertTrue(error is CancellationError || (error as NSError).code == NSURLErrorCancelled) }
        XCTAssertEqual(AnalystFaultProtocol.count(host), 1)
    }
}
