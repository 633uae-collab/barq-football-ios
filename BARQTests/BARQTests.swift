import XCTest
@testable import BARQ

final class BARQTests: XCTestCase {
    let sample = #"{"id":1,"date":"2026-11-01T00:00:00+04:00","ts":1793476800,"status":{"long":"Match Finished","short":"FT","elapsed":90,"extra":null},"venue":"X","referee":null,"league":{"id":39,"name":"PL","logo":null,"round":"R1","country":"England","season":2026},"home":{"id":1,"name":"A","logo":null,"winner":true},"away":{"id":2,"name":"B","logo":null,"winner":false},"goals":{"home":2,"away":1},"imp":12}"#

    func testDecodeFixture() throws {
        let f = try JSONDecoder().decode(Fixture.self, from: Data(sample.utf8))
        XCTAssertTrue(f.isDone); XCTAssertEqual(f.scoreText, "2 - 1"); XCTAssertEqual(f.importance, 12)
    }
    func testSortLiveFirstThenImportance() throws {
        var a = try JSONDecoder().decode(Fixture.self, from: Data(sample.utf8))
        var b = a; b.id = 2; b.imp = 50
        var c = a; c.id = 3; c.status.short = "2H"; c.imp = 1
        a.imp = 10
        XCTAssertEqual(MatchSort.byImportance([a, b, c]).map(\.id), [3, 2, 1])
    }
    func testInsightNums() throws {
        let j = #"{"tracking":1,"insights":[{"id":9,"fixture":5,"minute":45,"type":"ht","level":"low","team":"","title":"t","body":"b","nums":{"score":"0-0","x":3},"at":1793530253992,"k":"k","match":{"home":"A","away":"B"}}]}"#
        let r = try JSONDecoder().decode(FeedResponse.self, from: Data(j.utf8))
        XCTAssertEqual(r.insights[0].nums?["x"]?.text, "3"); XCTAssertEqual(r.insights[0].symbol, "pause.circle")
    }
}
