import XCTest
#if !LAUNCH_READINESS_STANDALONE
@testable import BARQ
#endif

final class LaunchCommitReadinessTests: XCTestCase {
    func testStableCommittedLayoutDoesNotDependOnCallbackCadence() {
        // The probe has no clock input: 16, 66 or 500 ms between completed
        // commits cannot invalidate an otherwise identical committed layout.
        var readiness = LaunchCommitReadiness()
        XCTAssertFalse(readiness.observe(layoutGeneration: 3, isActive: true))
        XCTAssertTrue(readiness.observe(layoutGeneration: 3, isActive: true))
    }

    func testChangingLayoutMustCommitAgainBeforeReveal() {
        var readiness = LaunchCommitReadiness()
        for generation in 1...10 {
            XCTAssertFalse(readiness.observe(layoutGeneration: generation, isActive: true))
        }
        XCTAssertTrue(readiness.observe(layoutGeneration: 10, isActive: true))
    }

    func testInactiveSceneCannotReusePreviousActiveCommit() {
        var readiness = LaunchCommitReadiness()
        XCTAssertFalse(readiness.observe(layoutGeneration: 2, isActive: true))
        XCTAssertFalse(readiness.observe(layoutGeneration: 2, isActive: false))
        XCTAssertFalse(readiness.observe(layoutGeneration: 2, isActive: true))
        XCTAssertTrue(readiness.observe(layoutGeneration: 2, isActive: true))
    }

    func testNoHostedLayoutCannotBeReady() {
        var readiness = LaunchCommitReadiness()
        for _ in 0..<10 {
            XCTAssertFalse(readiness.observe(layoutGeneration: 0, isActive: true))
        }
        XCTAssertFalse(readiness.observe(layoutGeneration: 1, isActive: true))
        XCTAssertTrue(readiness.observe(layoutGeneration: 1, isActive: true))
    }

    func testReplacementDestinationRequiresFreshStableCommits() {
        var readiness = LaunchCommitReadiness()
        XCTAssertFalse(readiness.observe(layoutGeneration: 4, isActive: true))
        XCTAssertTrue(readiness.observe(layoutGeneration: 4, isActive: true))
        XCTAssertFalse(readiness.observe(layoutGeneration: 0, isActive: true))
        XCTAssertFalse(readiness.observe(layoutGeneration: 1, isActive: true))
        XCTAssertTrue(readiness.observe(layoutGeneration: 1, isActive: true))
    }
}

