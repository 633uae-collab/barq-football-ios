import XCTest
@testable import BARQ

final class NotificationGroupingTests: XCTestCase {
    func ins(_ id: Int, fx: Int, at: Double, type: String = "goal", title: String = "t") -> Insight {
        Insight(id: id, fixture: fx, minute: 10, type: type, level: "high", team: nil, title: title, body: "b", nums: nil, at: at, match: nil)
    }
    func testDedupeAndGrouping() {
        let t0: Double = 1_790_000_000_000, day: Double = 86_400_000
        let list = [ins(1, fx: 7, at: t0), ins(1, fx: 7, at: t0), ins(2, fx: 7, at: t0 + 60_000, title: "x"), ins(3, fx: 8, at: t0 + 120_000),
                    ins(4, fx: 7, at: t0 - day, title: "y"), ins(5, fx: 7, at: t0 + 1000, title: "x")]
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Dubai")!
        XCTAssertEqual(NoteGrouping.dedupe(list).map(\.id), [1, 2, 3, 4])
        let g = NoteGrouping.groups(list, calendar: cal)
        XCTAssertEqual(g.map(\.fixture), [8, 7, 7])
        XCTAssertEqual(g[1].items.map(\.id), [2, 1])
    }
    func testFiltersPartitionTypes() {
        let all = ["goal", "red", "kickoff", "ht", "ft", "pressure", "shift", "possession"].enumerated().map { ins($0.offset, fx: 1, at: 0, type: $0.element, title: $0.element) }
        XCTAssertEqual(all.filter(NoteKind.all.match).count, all.count)
        XCTAssertEqual(all.filter(NoteKind.ai.match).map(\.type), ["pressure", "shift", "possession"])
        XCTAssertEqual(all.filter(NoteKind.goals.match).map(\.type), ["goal", "red", "kickoff"])
        XCTAssertEqual(all.filter(NoteKind.results.match).map(\.type), ["ht", "ft"])
    }
    func testNoEmDash() { XCTAssertEqual(NoteGrouping.clean("طرد — فريق"), "طرد · فريق") }
}
