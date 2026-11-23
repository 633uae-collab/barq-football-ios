import XCTest
@testable import BARQ

final class AnalystNetworkFailureTests: XCTestCase {
    func testInterruptedRequestDoesNotClaimSuccessOrAutomaticResend() {
        for english in [true, false] {
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost,
                userInfo: [NSLocalizedDescriptionKey: "secret-host / internal diagnostic"])
            let message = AnalystNetworkFailure.message(for: error, english: english)
            XCTAssertNotNil(message)
            XCTAssertFalse(message!.contains("secret-host"))
            XCTAssertTrue(message!.contains(english ? "not resent automatically" : "لم نُعد إرساله تلقائياً"))
        }
    }
    func testTLSAndTimeoutRemainDistinctAndUnknownErrorsAreNotMisclassified() {
        let tls = AnalystNetworkFailure.message(for: URLError(.secureConnectionFailed), english: true)!
        let timeout = AnalystNetworkFailure.message(for: URLError(.timedOut), english: true)!
        XCTAssertTrue(tls.contains("secure"))
        XCTAssertTrue(timeout.contains("time limit"))
        XCTAssertNotEqual(tls, timeout)
        XCTAssertNil(AnalystNetworkFailure.message(for: NSError(domain: "API", code: 503), english: true))
    }
}
