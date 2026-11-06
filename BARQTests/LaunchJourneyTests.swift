import XCTest
@testable import BARQ

final class LaunchJourneyTests: XCTestCase {
    func testFreshInstallThenInterruptedSelectionUsesQuickResume() {
        let name = "journey-\(UUID())"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        XCTAssertTrue(Onboarding.needsCinema(d))
        d.set(true, forKey: Onboarding.cinematicKey)
        XCTAssertFalse(Onboarding.needsCinema(d))
        XCTAssertFalse(Onboarding.isDone(d))
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
        XCTAssertFalse(Onboarding.needsCinema(d))
        XCTAssertNil(d.data(forKey: Onboarding.draftKey))
    }
    func testExistingCompletedUsersNeverReplayCinema() {
        let name = "journey-\(UUID())"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        d.set(true, forKey: Onboarding.doneKey)
        XCTAssertFalse(Onboarding.needsCinema(d))
    }
    func testCorruptDraftAndInvalidStepRecoverSafely() {
        let name = "journey-\(UUID())"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        d.set(Data("broken".utf8), forKey: Onboarding.draftKey)
        XCTAssertEqual(Onboarding.loadDraft(d).step, 0)
        Onboarding.saveDraft(.init(step: 99), d)
        XCTAssertEqual(Onboarding.loadDraft(d).step, 0)
        d.set(true, forKey: Onboarding.cinematicKey)
        d.set(true, forKey: "resetOnboarding")
        Onboarding.resetIfRequested(d)
        XCTAssertTrue(Onboarding.needsCinema(d))
        XCTAssertNil(d.data(forKey: Onboarding.draftKey))
    }
}
