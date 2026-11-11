import XCTest
#if !LAUNCH_READINESS_STANDALONE
@testable import BARQ
#endif

final class LaunchCommitReadinessTests: XCTestCase {
    func testStableCommittedLayoutDoesNotDependOnCallbackCadence() {
        // Long gaps do not prevent readiness; repeated update timestamps do.
        var readiness = LaunchCommitReadiness()
        var updateTime = 0.0
        func nextUpdate() -> Double { updateTime += 0.5; return updateTime }
        XCTAssertFalse(readiness.observe(layoutGeneration: 3, isActive: true, updateTime: nextUpdate()))
        XCTAssertTrue(readiness.observe(layoutGeneration: 3, isActive: true, updateTime: nextUpdate()))
    }

    func testChangingLayoutMustCommitAgainBeforeReveal() {
        var readiness = LaunchCommitReadiness()
        var updateTime = 0.0
        func nextUpdate() -> Double { updateTime += 0.5; return updateTime }
        for generation in 1...10 {
            XCTAssertFalse(readiness.observe(layoutGeneration: generation, isActive: true, updateTime: nextUpdate()))
        }
        XCTAssertTrue(readiness.observe(layoutGeneration: 10, isActive: true, updateTime: nextUpdate()))
    }

    func testInactiveSceneCannotReusePreviousActiveCommit() {
        var readiness = LaunchCommitReadiness()
        var updateTime = 0.0
        func nextUpdate() -> Double { updateTime += 0.5; return updateTime }
        XCTAssertFalse(readiness.observe(layoutGeneration: 2, isActive: true, updateTime: nextUpdate()))
        XCTAssertFalse(readiness.observe(layoutGeneration: 2, isActive: false, updateTime: nextUpdate()))
        XCTAssertFalse(readiness.observe(layoutGeneration: 2, isActive: true, updateTime: nextUpdate()))
        XCTAssertTrue(readiness.observe(layoutGeneration: 2, isActive: true, updateTime: nextUpdate()))
    }

    func testNoHostedLayoutCannotBeReady() {
        var readiness = LaunchCommitReadiness()
        var updateTime = 0.0
        func nextUpdate() -> Double { updateTime += 0.5; return updateTime }
        for _ in 0..<10 {
            XCTAssertFalse(readiness.observe(layoutGeneration: 0, isActive: true, updateTime: nextUpdate()))
        }
        XCTAssertFalse(readiness.observe(layoutGeneration: 1, isActive: true, updateTime: nextUpdate()))
        XCTAssertTrue(readiness.observe(layoutGeneration: 1, isActive: true, updateTime: nextUpdate()))
    }

    func testReplacementDestinationRequiresFreshStableCommits() {
        var readiness = LaunchCommitReadiness()
        var updateTime = 0.0
        func nextUpdate() -> Double { updateTime += 0.5; return updateTime }
        XCTAssertFalse(readiness.observe(layoutGeneration: 4, isActive: true, updateTime: nextUpdate()))
        XCTAssertTrue(readiness.observe(layoutGeneration: 4, isActive: true, updateTime: nextUpdate()))
        XCTAssertFalse(readiness.observe(layoutGeneration: 0, isActive: true, updateTime: nextUpdate()))
        XCTAssertFalse(readiness.observe(layoutGeneration: 1, isActive: true, updateTime: nextUpdate()))
        XCTAssertTrue(readiness.observe(layoutGeneration: 1, isActive: true, updateTime: nextUpdate()))
    }
    func testDuplicateUpdateCannotEstablishReadiness() {
        var readiness = LaunchCommitReadiness()
        XCTAssertFalse(readiness.observe(layoutGeneration: 2, isActive: true, updateTime: 10))
        XCTAssertFalse(readiness.observe(layoutGeneration: 2, isActive: true, updateTime: 10))
        XCTAssertTrue(readiness.observe(layoutGeneration: 2, isActive: true, updateTime: 10.016))
    }

    func testLayoutChangeWithinSameUpdateRequiresAnotherUpdate() {
        var readiness = LaunchCommitReadiness()
        XCTAssertFalse(readiness.observe(layoutGeneration: 1, isActive: true, updateTime: 10))
        XCTAssertFalse(readiness.observe(layoutGeneration: 2, isActive: true, updateTime: 10))
        XCTAssertFalse(readiness.observe(layoutGeneration: 2, isActive: true, updateTime: 10))
        XCTAssertTrue(readiness.observe(layoutGeneration: 2, isActive: true, updateTime: 10.5))
    }
}

