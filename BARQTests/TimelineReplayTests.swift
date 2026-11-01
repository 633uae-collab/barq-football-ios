import XCTest
@testable import BARQ

/// Uses REAL backend responses: a finished match with 45+3 / 90+5 events, and snapshot sequences
/// recorded every ~60s from live matches on 2026-11-02 (files replay-<fixture>-<step>.json). Not mock data.
final class TimelineReplayTests: XCTestCase {
    func load(_ url: URL) throws -> MatchDetail { try JSONDecoder().decode(MatchDetail.self, from: Data(contentsOf: url)) }

    func testRealStoppageTimeOrdering() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "real-match-1559185", withExtension: "json"))
        let d = try load(url)
        let rows = TimelineOrder.keyed(d.events, status: d.match.status.short)
        let labels = rows.map { r -> String in
            if case .event(_, let e) = r.row { return "\(e.time.elapsed ?? 0)+\(e.time.extra ?? 0)" }
            if case .marker(let m) = r.row { return m.rawValue }
            return ""
        }
        let ht = try XCTUnwrap(labels.firstIndex(of: "ht"))
        XCTAssertEqual(labels.first, "ft"); XCTAssertEqual(labels.last, "kickoff")
        XCTAssertLessThan(try XCTUnwrap(labels.firstIndex(of: "90+6")), try XCTUnwrap(labels.firstIndex(of: "90+5")))
        XCTAssertLessThan(try XCTUnwrap(labels.firstIndex(of: "90+5")), try XCTUnwrap(labels.firstIndex(of: "90+3")))
        XCTAssertGreaterThan(try XCTUnwrap(labels.firstIndex(of: "45+3")), ht, "45+3 belongs below the HT marker")
        XCTAssertTrue(labels[..<ht].allSatisfy { $0 == "ft" || (Int($0.split(separator: "+")[0]) ?? 0) >= 46 }, "only 2nd-half events above HT: \(labels)")
        XCTAssertEqual(Set(rows.map(\.key)).count, rows.count)
    }

    func testReplayOfRecordedLiveSnapshots() throws {
        let urls = (Bundle(for: Self.self).urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("replay-") }
        try XCTSkipIf(urls.isEmpty, "no recorded snapshots bundled")
        let byFixture = Dictionary(grouping: urls) { $0.lastPathComponent.split(separator: "-")[1] }
        var transitions = 0
        for (fx, list) in byFixture {
            var prev: [String] = []
            for u in list.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let d = try load(u)
                let cur = TimelineOrder.keyed(d.events, status: d.match.status.short).map(\.key)
                XCTAssertEqual(Set(cur).count, cur.count, "dup in \(u.lastPathComponent)")
                XCTAssertEqual(cur.last, "m-kickoff")
                let kept = prev.filter { cur.contains($0) }
                XCTAssertEqual(kept, cur.filter { prev.contains($0) }, "order of existing rows changed \(fx) \(u.lastPathComponent)")
                let gone = prev.filter { !cur.contains($0) }
                // A key may only vanish when API-SPORTS corrects that event in place (same number of rows of that type),
                // e.g. fixture 1490597 moved an unattributed goal 10' -> 22' and then added the scorer.
                func count(_ k: [String], _ t: String) -> Int { k.filter { $0.hasPrefix(t + "|") }.count }
                let churn = gone.filter { g in let t = String(g.split(separator: "|")[0]); return count(cur, t) < count(prev, t) }
                XCTAssertTrue(churn.isEmpty, "row disappeared \(fx) \(u.lastPathComponent): \(churn)")
                let newEvents = cur.filter { !prev.contains($0) && !$0.hasPrefix("m-") }
                if !prev.isEmpty, let n = newEvents.first, let oldTop = prev.first(where: { !$0.hasPrefix("m-") }) {
                    // a newly reported latest event is above the previous top event
                    func m(_ k: String) -> Int { let p = k.split(separator: "|"); return (Int(p[1]) ?? 0) * 100 + (Int(p[2]) ?? 0) }
                    if m(n) > m(oldTop), let iN = cur.firstIndex(of: n), let iO = cur.firstIndex(of: oldTop) { XCTAssertLessThan(iN, iO) }
                    transitions += 1
                }
                prev = cur
            }
        }
        print("REPLAY_UNIT fixtures=\(byFixture.count) new-event transitions=\(transitions)")
    }
}
