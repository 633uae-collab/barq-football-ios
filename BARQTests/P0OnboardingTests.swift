import XCTest
@testable import BARQ

final class P0OnboardingTests: XCTestCase {
    @MainActor func testFirstLaunchCanChooseClubEvenWhenEveryRequestFails() async {
        let name = "clubs-\(UUID())"
        // Explicit suite below is isolated from the actual app's preferences.
        let isolated = UserDefaults(suiteName: name)!
        defer { isolated.removePersistentDomain(forName: name) }
        let model = ClubPickerModel(defaults: isolated)
        XCTAssertFalse(model.popular.isEmpty)
        await model.loadPopular(fetch: { _ in throw APIError.offline })
        XCTAssertFalse(model.loading); XCTAssertNotNil(model.error)
        let store = AppStore(defaults: isolated, syncEnabled: false)
        Onboarding.apply(clubs: [model.popular[0]], leagues: [], cups: [], to: store)
        Onboarding.markDone(isolated)
        XCTAssertTrue(isolated.bool(forKey: Onboarding.doneKey))
        XCTAssertEqual(AppStore(defaults: isolated, syncEnabled: false).favTeams, store.favTeams)
    }
    @MainActor func testEmptySearchFinishesWithoutInfiniteSpinner() async throws {
        let model = ClubPickerModel()
        let empty = try JSONDecoder().decode(SearchResponse.self, from: Data("{\"q\":\"missing\",\"leagues\":[],\"teams\":[],\"players\":[],\"matches\":[]}".utf8))
        await model.search("missing", fetch: { _ in empty })
        XCTAssertFalse(model.searching); XCTAssertTrue(model.results.isEmpty); XCTAssertNil(model.searchError)
    }
    @MainActor func testFailedSearchKeepsLocalMatchesAndCanRetry() async throws {
        let model = ClubPickerModel()
        model.popular = ClubDirectory.bundled
        await model.search("ليفربول", fetch: { _ in throw APIError.offline })
        XCTAssertFalse(model.searching); XCTAssertNotNil(model.searchError); XCTAssertEqual(model.results.map(\.id), [40])
        let response = try JSONDecoder().decode(SearchResponse.self, from: Data("{\"q\":\"Liverpool\",\"leagues\":[],\"teams\":[{\"id\":40,\"name\":\"Liverpool\"}],\"players\":[],\"matches\":[]}".utf8))
        await model.search("Liverpool", fetch: { _ in response })
        XCTAssertNil(model.searchError); XCTAssertFalse(model.searching); XCTAssertEqual(model.results.map(\.id), [40])
    }
    func testCachedDirectorySurvivesRelaunchWithoutChangingIdentity() throws {
        let name = "clubs-\(UUID())"
        let isolated = UserDefaults(suiteName: name)!
        defer { isolated.removePersistentDomain(forName: name) }
        let clubs = [TeamRef(id: 40, name: "Liverpool", logo: nil)]
        isolated.set(try JSONEncoder().encode(clubs), forKey: ClubDirectory.cacheKey)
        XCTAssertEqual(ClubDirectory.initial(isolated), clubs)
    }
}
