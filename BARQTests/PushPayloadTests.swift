import XCTest
import ActivityKit
@testable import BARQ

/// Verifies the APNs payloads produced by backend-addons/push.js (dumped from a real fixture into Payloads/)
/// decode into the exact Swift types the app and widget use.
final class PushPayloadTests: XCTestCase {
    func payload(_ name: String) throws -> [String: Any] {
        let b = Bundle(for: Self.self)
        let url = try XCTUnwrap(b.url(forResource: name, withExtension: nil) ?? b.url(forResource: name, withExtension: nil, subdirectory: "Payloads"), "missing \(name)")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    func aps(_ name: String) throws -> [String: Any] { try XCTUnwrap(payload(name)["aps"] as? [String: Any]) }
    func decode<T: Decodable>(_ o: Any, _ t: T.Type) throws -> T { try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: o)) }

    func testContentStateRoundTrip() throws {
        let s = MatchActivityAttributes.ContentState(homeGoals: 2, awayGoals: 1, minute: 63, status: "2H", lastEvent: "هدف - صلاح 63'", insight: "ضغط")
        let back = try JSONDecoder().decode(MatchActivityAttributes.ContentState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(s, back)
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any]).keys
        XCTAssertEqual(Set(keys), ["homeGoals", "awayGoals", "minute", "status", "lastEvent", "insight"])
    }
    func testLiveUpdatePayloadDecodes() throws {
        let a = try aps("live-update.json")
        XCTAssertEqual(a["event"] as? String, "update")
        XCTAssertNotNil(a["timestamp"] as? Int)
        let s = try decode(XCTUnwrap(a["content-state"]), MatchActivityAttributes.ContentState.self)
        XCTAssertEqual(s.status, "2H")
    }
    func testLiveEndPayload() throws {
        let a = try aps("live-end.json")
        XCTAssertEqual(a["event"] as? String, "end")
        XCTAssertNotNil(a["dismissal-date"])
        _ = try decode(XCTUnwrap(a["content-state"]), MatchActivityAttributes.ContentState.self)
    }
    func testPushToStartPayload() throws {
        let a = try aps("push-to-start.json")
        XCTAssertEqual(a["event"] as? String, "start")
        XCTAssertEqual(a["attributes-type"] as? String, String(describing: MatchActivityAttributes.self))
        let attrs = try decode(XCTUnwrap(a["attributes"]), MatchActivityAttributes.self)
        XCTAssertGreaterThan(attrs.fixtureId, 0)
        _ = try decode(XCTUnwrap(a["content-state"]), MatchActivityAttributes.ContentState.self)
        XCTAssertNotNil(a["alert"])
    }
    func testAlertPayloadDeepLinksToFixture() throws {
        let p = try payload("alert.json")
        let fixture = try XCTUnwrap(p["fixture"] as? Int)
        let alert = try XCTUnwrap((p["aps"] as? [String: Any])?["alert"] as? [String: Any])
        XCTAssertFalse((alert["title"] as? String ?? "").isEmpty)
        XCTAssertEqual((p["aps"] as? [String: Any])?["thread-id"] as? String, "fixture-\(fixture)")
    }
    func testLocalNotificationMatchesAPNsShape() throws {
        let i = Insight(id: 7, fixture: 99, minute: 50, type: "red", level: "high", team: nil, title: "t", body: "b", nums: nil, at: 0, match: nil)
        let c = Notifier.content(for: i)
        XCTAssertEqual(c.threadIdentifier, "fixture-99")
        XCTAssertEqual(c.userInfo["fixture"] as? Int, 99)
        XCTAssertEqual(c.interruptionLevel, .timeSensitive)
    }
    func testDensityFilter() {
        func ins(_ t: String, _ l: String) -> Insight { Insight(id: 1, fixture: 1, minute: 1, type: t, level: l, team: nil, title: "", body: "", nums: nil, at: 0, match: nil) }
        XCTAssertTrue(Notifier.allowed(ins("ft", "low"), density: 0))
        XCTAssertFalse(Notifier.allowed(ins("pressure", "high"), density: 0))
        XCTAssertTrue(Notifier.allowed(ins("pressure", "high"), density: 1))
        XCTAssertFalse(Notifier.allowed(ins("possession", "medium"), density: 1))
        XCTAssertTrue(Notifier.allowed(ins("possession", "medium"), density: 2))
    }
    func testStateFromRealEvents() throws {
        let j = #"{"match":{"id":1,"date":"","ts":0,"status":{"short":"2H","elapsed":70},"league":{"id":1,"name":"L"},"home":{"id":1,"name":"A"},"away":{"id":2,"name":"B"},"goals":{"home":1,"away":0}},"events":[{"time":{"elapsed":12},"team":{"id":1,"name":"A"},"player":{"id":5,"name":"Salah"},"type":"Goal","detail":"Normal Goal"},{"time":{"elapsed":40},"team":{"id":2,"name":"B"},"type":"subst"}],"lineups":[],"statistics":[]}"#
        let d = try JSONDecoder().decode(MatchDetail.self, from: Data(j.utf8))
        let s = MatchActivityAttributes.ContentState.from(d)
        XCTAssertEqual(s.minute, 70); XCTAssertEqual(s.homeGoals, 1); XCTAssertEqual(s.lastEvent, "هدف - Salah 12'")
    }
}
