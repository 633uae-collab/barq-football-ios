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
        let clubs = [TeamRef(id: 990001, name: "Saved club outside the seven leagues", logo: nil)]
        isolated.set(try JSONEncoder().encode(clubs), forKey: ClubDirectory.cacheKey)
        let restored = ClubDirectory.initial(isolated)
        XCTAssertEqual(restored.filter { $0.id == clubs[0].id }, clubs)
        XCTAssertTrue(restored.contains { $0.id == 529 })
    }

    @MainActor func testAllGroupsRefreshWithoutDroppingOfflineLeaguesAndArabicSearchMatches() async throws {
        let name = "club-groups-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = ClubDirectory.snapshot
        for id in ClubDirectory.sources {
            XCTAssertGreaterThan(directory.clubs[String(id)]?.count ?? 0, 8)
        }
        XCTAssertTrue(directory.competitions.contains { $0.id == 2 && $0.type == "Cup" })
        let model = ClubPickerModel(defaults: defaults)
        let teams = (1...10).map { TeamRef(id: 990000 + $0, name: "Test club \($0)") }
        let rows = teams.map { StandingRow(rank: 1, team: $0, points: 0) }
        await model.loadPopular { league in
            if league != 39 { throw APIError.offline }
            return StandingsResponse(league: LeagueMeta(id: 39, name: "Test league"), groups: [Array(rows.prefix(9)), [rows[9], rows[0]]])
        }
        let saved = ClubDirectory.initial(defaults)
        XCTAssertTrue(teams.allSatisfy { saved.contains($0) })
        XCTAssertEqual(saved.filter { $0.id == teams[0].id }.count, 1)
        XCTAssertTrue(saved.contains { $0.id == 2865 })
        let empty = try JSONDecoder().decode(SearchResponse.self, from: Data(#"{"q":"برشلونة","leagues":[],"teams":[],"players":[],"matches":[]}"#.utf8))
        await model.search("برشلونة", fetch: { _ in empty })
        XCTAssertEqual(model.results.map(\.id), [529])
        await model.search("Ba", fetch: { _ in XCTFail("Two characters should search locally"); return empty })
        XCTAssertTrue(model.results.contains { $0.id == 529 })
    }
}
