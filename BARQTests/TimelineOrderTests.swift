import XCTest
@testable import BARQ

final class TimelineOrderTests: XCTestCase {
    func ev(_ m: Int, _ x: Int? = nil, _ type: String = "Goal", team: Int = 1) -> MatchEvent {
        MatchEvent(time: EventTime(elapsed: m, extra: x), team: TeamRef(id: team, name: "T\(team)"), player: NamedRef(id: m, name: "P\(m)"), assist: nil, type: type, detail: nil)
    }
    func minutes(_ rows: [TimelineOrder.Row]) -> [String] {
        rows.map { r in
            switch r {
            case .marker(let m): return m.rawValue
            case .event(_, let e): return "\(e.time.elapsed ?? 0)" + (e.time.extra.map { "+\($0)" } ?? "")
            }
        }
    }
    func testDescendingKickoffLast() {
        let r = TimelineOrder.rows([ev(14), ev(30), ev(60), ev(75), ev(90)], status: "2H")
        XCTAssertEqual(minutes(r), ["90", "75", "60", "ht", "30", "14", "kickoff"])
    }
    func testExtraTimeAndFullTime() {
        let r = TimelineOrder.rows([ev(45, 2, "Card"), ev(45), ev(90, 4), ev(90), ev(46, nil, "subst")], status: "FT")
        XCTAssertEqual(minutes(r), ["ft", "90+4", "90", "46", "ht", "45+2", "45", "kickoff"])
    }
    func testTiesKeepLaterApiEventOnTop() {
        let a = ev(60, nil, "subst", team: 1), b = ev(60, nil, "Card", team: 2)
        let r = TimelineOrder.rows([a, b], status: "2H")
        guard case .event(let i, _) = r[0] else { return XCTFail() }
        XCTAssertEqual(i, 1)
    }
    func testFirstHalfNoMarkers() {
        XCTAssertEqual(minutes(TimelineOrder.rows([ev(5), ev(20)], status: "1H")), ["20", "5", "kickoff"])
    }
}
