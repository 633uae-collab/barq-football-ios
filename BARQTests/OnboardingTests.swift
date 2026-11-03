import XCTest
@testable import BARQ

/// First-launch flag + saving onboarding choices into the existing favorites (AppStore), persisted across instances.
/// IDs below are real API-Football IDs (Liverpool 40, Real Madrid 541, Premier League 39, Champions League 2).
final class OnboardingTests: XCTestCase {
    var saved: [String: Any] = [:]
    let keys = ["onboardingDone", "favTeams", "favLeagues", "resetOnboarding"]
    override func setUp() { let d = UserDefaults.standard; for k in keys { saved[k] = d.object(forKey: k); d.removeObject(forKey: k) } }
    override func tearDown() { let d = UserDefaults.standard; for k in keys { if let v = saved[k] { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } } }

    func testFlagPersists() {
        let d = UserDefaults(suiteName: "ob-\(UUID())")!
        XCTAssertFalse(d.bool(forKey: Onboarding.doneKey))
        Onboarding.markDone(d)
        XCTAssertTrue(d.bool(forKey: Onboarding.doneKey))
    }
    func testResetOnlyWhenRequested() {
        let d = UserDefaults(suiteName: "ob-\(UUID())")!
        Onboarding.markDone(d); d.set(Data("[]".utf8), forKey: "favTeams")
        Onboarding.resetIfRequested(d)
        XCTAssertTrue(d.bool(forKey: Onboarding.doneKey))
        d.set(true, forKey: "resetOnboarding"); Onboarding.resetIfRequested(d)
        XCTAssertFalse(d.bool(forKey: Onboarding.doneKey)); XCTAssertNil(d.data(forKey: "favTeams"))
    }
    func testApplySavesIntoFavoritesAndSurvivesRelaunch() {
        let s = AppStore()
        Onboarding.apply(clubs: [TeamRef(id: 40, name: "Liverpool", logo: "https://media.api-sports.io/football/teams/40.png"),
                                 TeamRef(id: 541, name: "Real Madrid", logo: nil), TeamRef(id: 40, name: "Liverpool", logo: nil)],
                         leagues: [39], cups: [2, 39], to: s)
        XCTAssertEqual(s.favTeams.map(\.id), [40, 541], "no duplicates, order kept")
        XCTAssertEqual(s.favLeagues, [39, 2])
        let relaunched = AppStore()
        XCTAssertEqual(relaunched.favTeams.map(\.id), [40, 541])
        XCTAssertEqual(relaunched.favLeagues, [39, 2])
        XCTAssertTrue(relaunched.isFav(team: 40))
    }
    func testSkippingCompetitionsKeepsDefaultLeagues() {
        let s = AppStore(); let before = s.favLeagues
        Onboarding.apply(clubs: [TeamRef(id: 50, name: "Manchester City", logo: nil)], leagues: [], cups: [], to: s)
        XCTAssertEqual(s.favLeagues, before); XCTAssertFalse(before.isEmpty)
        XCTAssertEqual(AppStore().favTeams.map(\.id), [50])
    }
}
