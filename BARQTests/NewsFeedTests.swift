import XCTest
@testable import BARQ

final class NewsFeedTests: XCTestCase {
    func club(_ id: Int, _ name: String, _ transfers: [Transfer]) -> NewsClub {
        NewsClub(id: id, name: name, logo: nil, transfers: transfers)
    }
    func move(player: Int, name: String, date: String, type: String, from: Int, to: Int) -> Transfer {
        Transfer(player: NamedRef(id: player, name: name), date: date, type: type,
                 in: LooseRef(id: to, name: "In\(to)", logo: nil, season: nil),
                 out: LooseRef(id: from, name: "Out\(from)", logo: nil, season: nil))
    }

    func testNewestFirstAndBlankTypeDropped() {
        let items = NewsFeed.items([
            club(40, "Liverpool", [
                move(player: 1, name: "Older", date: "2024-01-01", type: "Loan", from: 40, to: 1),
                move(player: 2, name: "Newer", date: "2026-08-31", type: "-", from: 40, to: 2),
            ]),
        ])
        let shown = NewsFeed.visible(items, team: nil)
        XCTAssertEqual(shown.map(\.player), ["Newer", "Older"])
        XCTAssertEqual(shown[0].type, "")
        XCTAssertEqual(shown[1].type, "Loan")
    }

    func testAllDedupesAMoveListedByTwoFavourites() {
        let deal = move(player: 7, name: "Shared", date: "2026-07-01", type: "Transfer", from: 40, to: 50)
        let items = NewsFeed.items([
            club(40, "Liverpool", [deal]),
            club(50, "City", [deal]),
        ])
        XCTAssertEqual(NewsFeed.visible(items, team: nil).map(\.sourceTeam), [40])
        XCTAssertEqual(NewsFeed.visible(items, team: 50).map(\.sourceTeam), [50])
        XCTAssertEqual(NewsFeed.teams(items).map(\.id), [40, 50])
    }

    func testVisibleLimit() {
        let transfers = (0..<50).map { move(player: $0, name: "P\($0)", date: String(format: "2026-01-%02d", ($0 % 28) + 1), type: "Loan", from: 1, to: 2) }
        let shown = NewsFeed.visible(NewsFeed.items([club(1, "A", transfers)]), team: nil, limit: 40)
        XCTAssertEqual(shown.count, 40)
    }

    func testRealTeamPayloadFeedsNews() throws {
        let b = Bundle(for: Self.self)
        let url = try XCTUnwrap(b.url(forResource: "real-team-40", withExtension: "json"))
        let team = try JSONDecoder().decode(TeamResponse.self, from: Data(contentsOf: url))
        let club = NewsClub(id: 40, name: team.team?.name ?? "", logo: team.team?.logo, transfers: team.transfers ?? [])
        let shown = NewsFeed.visible(NewsFeed.items([club]), team: 40)
        XCTAssertFalse(shown.isEmpty)
        XCTAssertEqual(shown.first?.date, "2026-08-31")
        XCTAssertTrue(shown.allSatisfy { $0.sourceTeam == 40 })
    }
}
