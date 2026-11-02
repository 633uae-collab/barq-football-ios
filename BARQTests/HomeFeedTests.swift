import XCTest
@testable import BARQ

/// Home v8 rules with an injected clock and test-only fixtures (never shipped in the app).
final class HomeFeedTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_793_600_000)
    func fx(_ id: Int, inMin: Double, status: String = "NS", home: Int = 100, away: Int = 200, league: Int = 39, elapsed: Int? = nil) -> Fixture {
        Fixture(id: id, date: "", ts: Int(now.timeIntervalSince1970 + inMin * 60), status: .init(long: nil, short: status, elapsed: elapsed, extra: nil),
                venue: nil, referee: nil, league: .init(id: league, name: "L\(league)"),
                home: .init(id: home + id, name: "H\(id)"), away: .init(id: away + id, name: "A\(id)"), goals: .init(home: 1, away: 0), imp: nil)
    }
    func favs(_ ids: Int...) -> HomeFeed.Favorites { .init(matches: Set(ids)) }

    // (1) favorite more than 1 h away is not in the top card
    func test01_FavoriteMoreThanHourAwayNotInHero() {
        XCTAssertTrue(HomeFeed.hero([fx(1, inMin: 61)], favorites: favs(1), now: now).isEmpty)
        XCTAssertEqual(HomeFeed.upcoming([fx(1, inMin: 61)], now: now).map(\.id), [1])
    }
    // (2) at 60 min it appears, with a countdown
    func test02_AtSixtyMinutesAppearsWithCountdown() {
        let f = fx(1, inMin: 60)
        XCTAssertEqual(HomeFeed.hero([f], favorites: favs(1), now: now).map(\.id), [1])
        XCTAssertEqual(HomeFeed.countdown(to: f.kickoff, now: now), "1:00:00")
        XCTAssertEqual(HomeFeed.countdown(to: f.kickoff, now: now.addingTimeInterval(1)), "59:59")
        XCTAssertEqual(HomeFeed.countdown(to: f.kickoff, now: now.addingTimeInterval(3599)), "00:01")
        // not a favorite -> never in hero
        XCTAssertTrue(HomeFeed.hero([f], favorites: favs(), now: now).isEmpty)
    }
    // (3) lineups available -> button (decided by MatchDetail.lineups.count >= 2)
    func test03_LineupsDecode() throws {
        let j = #"{"match":{"id":1,"date":"","ts":1,"status":{"short":"NS"},"league":{"id":1,"name":"L"},"home":{"id":1,"name":"A"},"away":{"id":2,"name":"B"},"goals":{}},"events":[],"statistics":[],"lineups":[{"team":{"id":1,"name":"A"},"formation":"4-3-3","startXI":[]},{"team":{"id":2,"name":"B"},"formation":"4-4-2","startXI":[]}]}"#
        let d = try JSONDecoder().decode(MatchDetail.self, from: Data(j.utf8))
        XCTAssertGreaterThanOrEqual(d.lineups.count, 2)
    }
    // (4) kickoff: status turns live -> stays in hero as live (score + minute), incl. HT/ET/penalties
    func test04_KickoffSwitchesToLive() {
        for s in ["1H", "HT", "2H", "ET", "BT", "P"] {
            let f = fx(1, inMin: -50, status: s, elapsed: 50)
            XCTAssertTrue(f.isLive); XCTAssertEqual(HomeFeed.hero([f], favorites: favs(1), now: now).map(\.id), [1], s)
        }
        XCTAssertEqual(HomeFeed.countdown(to: fx(1, inMin: -1).kickoff, now: now), "00:00")
    }
    // (5) multiple favorites: stable order (live first, then soonest) and selection survives refresh
    func test05_MultipleFavoritesOrderAndSelection() {
        let list = [fx(3, inMin: 40), fx(1, inMin: 10), fx(2, inMin: -30, status: "2H")]
        let hero = HomeFeed.hero(list, favorites: favs(1, 2, 3), now: now)
        XCTAssertEqual(hero.map(\.id), [2, 1, 3])
        // user swiped to match 3; a refresh reorders nothing and keeps 3 selected
        let refreshed = HomeFeed.hero(list.reversed(), favorites: favs(1, 2, 3), now: now.addingTimeInterval(20))
        XCTAssertEqual(refreshed.map(\.id), [2, 1, 3])
        XCTAssertEqual(HomeFeed.keepSelection(3, in: refreshed.map(\.id)), 3)
        XCTAssertEqual(HomeFeed.keepSelection(9, in: refreshed.map(\.id)), 2)
    }
    // (6) FT removed from hero; postponed removed too
    func test06_FinishedAndPostponedRemoved() {
        for s in ["FT", "AET", "PEN", "PST", "CANC"] {
            XCTAssertTrue(HomeFeed.hero([fx(1, inMin: -100, status: s)], favorites: favs(1), now: now).isEmpty, s)
        }
        // rescheduled: new timestamp drives eligibility/countdown
        XCTAssertTrue(HomeFeed.hero([fx(1, inMin: 180)], favorites: favs(1), now: now).isEmpty)
    }
    // (7) empty state when nothing qualifies
    func test07_EmptyWhenNothingEligible() {
        XCTAssertTrue(HomeFeed.hero([fx(1, inMin: 300), fx(2, inMin: -200, status: "FT")], favorites: favs(1, 2), now: now).isEmpty)
    }
    // (8) adding a favorite (team / competition / match) makes an eligible match appear; prefs persist in UserDefaults
    func test08_AddingFavoriteAppearsAndPersists() {
        let f = fx(7, inMin: 30, league: 999)
        XCTAssertTrue(HomeFeed.hero([f], favorites: .init(), now: now).isEmpty)
        XCTAssertEqual(HomeFeed.hero([f], favorites: .init(teams: [f.home.id]), now: now).count, 1)
        XCTAssertEqual(HomeFeed.hero([f], favorites: .init(leagues: [999]), now: now).count, 1)
        let store = AppStore()
        let had = store.savedMatches.contains(424242)
        if !had { store.toggleSaved(424242) }
        XCTAssertTrue(AppStore().savedMatches.contains(424242), "persisted across a fresh store (app restart)")
        store.toggleSaved(424242)
        XCTAssertFalse(AppStore().savedMatches.contains(424242))
    }
    // (9) stars rotation order and decoding of real-shaped payload
    func test09_StarsRotationAndDecode() throws {
        XCTAssertEqual(HomeFeed.nextStar(1, in: [1, 2, 3]), 2)
        XCTAssertEqual(HomeFeed.nextStar(3, in: [1, 2, 3]), 1)
        XCTAssertNil(HomeFeed.nextStar(nil, in: []))
        let j = #"{"date":"2026-11-02","players":[{"id":5,"name":"P","photo":"https://x/p.png","team":{"id":1,"name":"T","logo":null},"fixture":9,"rating":7.5,"goals":1,"assists":0}]}"#
        let r = try JSONDecoder().decode(StarsResponse.self, from: Data(j.utf8))
        XCTAssertEqual(r.players.first?.goals, 1)
    }
    // (10) upcoming sorted soonest first, no duplicates, started matches excluded
    func test10_UpcomingSortedNoDuplicates() {
        let list = [fx(3, inMin: 300), fx(1, inMin: 20), fx(1, inMin: 20), fx(2, inMin: -10, status: "1H"), fx(4, inMin: 90), fx(5, inMin: -5)]
        XCTAssertEqual(HomeFeed.upcoming(list, now: now).map(\.id), [1, 4, 3])
    }
    func testDefaultSectionsOrder() { XCTAssertEqual(AppStore.defaultSections, ["carousel", "stars", "upcoming"]) }
}
