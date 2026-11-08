import XCTest
@testable import BARQ

final class LaunchJourneyTests: XCTestCase {
    func testFreshInstallThenInterruptedSelectionStillNeedsOnboarding() {
        let name = "journey-\(UUID())"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        XCTAssertFalse(Onboarding.isDone(d))
        d.set(true, forKey: "onboardingCinematicSeen") // Legacy flag must not control navigation.
        XCTAssertFalse(Onboarding.isDone(d))
        XCTAssertEqual(Onboarding.loadDraft(d).step, 0)
    }
    func testDraftRestoresStepAndAllSelectionsAcrossInstances() {
        let name = "journey-\(UUID())"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        Onboarding.saveDraft(.init(step: 2, clubs: [TeamRef(id: 40, name: "Liverpool", logo: nil)], leagues: [39], cups: [2]), d)
        let restored = Onboarding.loadDraft(UserDefaults(suiteName: name)!)
        XCTAssertEqual(restored.step, 2)
        XCTAssertEqual(restored.clubs.map(\.id), [40])
        XCTAssertEqual(restored.leagues, [39])
        XCTAssertEqual(restored.cups, [2])
        Onboarding.markDone(d)
        XCTAssertTrue(Onboarding.isDone(d))
        XCTAssertNil(d.data(forKey: Onboarding.draftKey))
    }
    func testExistingCompletedUsersOpenHome() {
        let name = "journey-\(UUID())"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        d.set(true, forKey: Onboarding.doneKey)
        XCTAssertTrue(Onboarding.isDone(d))
    }
    func testCorruptDraftAndInvalidStepRecoverSafely() {
        let name = "journey-\(UUID())"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        d.set(Data("broken".utf8), forKey: Onboarding.draftKey)
        XCTAssertEqual(Onboarding.loadDraft(d).step, 0)
        Onboarding.saveDraft(.init(step: 99), d)
        XCTAssertEqual(Onboarding.loadDraft(d).step, 0)
        d.set(true, forKey: "onboardingCinematicSeen") // Legacy flag must not control navigation.
        d.set(true, forKey: "resetOnboarding")
        Onboarding.resetIfRequested(d)
        XCTAssertFalse(Onboarding.isDone(d))
        XCTAssertNil(d.data(forKey: Onboarding.draftKey))
    }
}
