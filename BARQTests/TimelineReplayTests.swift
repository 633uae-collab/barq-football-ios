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

    /// Transient drop: replays every recorded REAL snapshot, and between two real snapshots feeds a response in which
    /// API-SPORTS returned a shorter list (the newest real events missing), then the next real snapshot.
    /// No previously shown event may disappear or duplicate, and a real removal is accepted only after maxMisses responses.
    func testTransientDropSnapshotKeepsEvents() throws {
        let urls = (Bundle(for: Self.self).urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("replay-") }
        try XCTSkipIf(urls.isEmpty, "no recorded snapshots bundled")
        var checked = 0
        for (_, list) in Dictionary(grouping: urls, by: { $0.lastPathComponent.split(separator: "-")[1] }) {
            var st = TimelineOrder.Stabilizer(); var shown: [MatchEvent] = []
            for u in list.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let real = try load(u).events
                var feed = [real]
                if real.count > 1 { feed = [Array(real.prefix(real.count / 2)), real] }   // transient drop, then recovery
                for incoming in feed {
                    let before = Set(TimelineOrder.keyedEvents(shown).map(\.0))
                    shown = st.merge(previous: shown, incoming: incoming)
                    let keys = TimelineOrder.keyed(shown, status: "2H").map(\.key)
                    XCTAssertEqual(Set(keys).count, keys.count, "duplicate after merge \(u.lastPathComponent)")
                    // only an in-place API revision (new key of same type+team) may replace a row
                    func slot(_ k: String) -> String { let p = k.split(separator: "|", omittingEmptySubsequences: false); return p.count > 4 ? "\(p[0])|\(p[4])" : k }
                    let added = Set(keys).subtracting(before).map(slot)
                    let vanished = before.subtracting(keys).filter { !added.contains(slot($0)) }
                    XCTAssertTrue(vanished.isEmpty, "event vanished on transient drop \(u.lastPathComponent): \(vanished)")
                    checked += 1
                }
            }
        }
        // A genuine removal (e.g. a goal deleted by the API after VAR) disappears after maxMisses responses, not before.
        let real = try XCTUnwrap(urls.lazy.map { try? self.load($0).events }.first { ($0?.count ?? 0) > 1 } ?? nil)
        var st = TimelineOrder.Stabilizer(); var shown = st.merge(previous: [], incoming: real)
        let revised = Array(real.dropLast())
        for i in 1...TimelineOrder.Stabilizer.maxMisses {
            shown = st.merge(previous: shown, incoming: revised)
            XCTAssertEqual(shown.count, i < TimelineOrder.Stabilizer.maxMisses ? real.count : revised.count, "miss \(i)")
        }
        print("TRANSIENT_DROP_UNIT responses=\(checked)")
    }

    /// Scorer filled in on a later refresh (seen live: goal 69' first reported without player) keeps the same row identity.
    func testGoalScorerFilledLaterKeepsIdentity() throws {
        let urls = (Bundle(for: Self.self).urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
        let goal = try XCTUnwrap(urls.lazy.compactMap { try? self.load($0).events.first { $0.type.lowercased() == "goal" && $0.player != nil } }.first)
        var unattributed = goal; unattributed.player = nil
        XCTAssertEqual(TimelineOrder.key(goal), TimelineOrder.key(unattributed))
    }

    func testCorrectedGoalMinuteKeepsDisplayedRowIdentity() throws {
        let urls = (Bundle(for: Self.self).urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
        let goal = try XCTUnwrap(urls.lazy.compactMap { try? self.load($0).events.first { $0.type.lowercased() == "goal" } }.first)
        var first = goal; first.time.elapsed = (goal.time.elapsed ?? 1) + 1; first.player = nil
        var stabilizer = TimelineOrder.Stabilizer()
        stabilizer.seed([first])
        let original = try XCTUnwrap(stabilizer.aliases[TimelineOrder.key(first)])
        let shown = stabilizer.merge(previous: [first], incoming: [goal])
        XCTAssertEqual(shown, [goal], "corrected provider content must replace the old event")
        XCTAssertEqual(stabilizer.aliases[TimelineOrder.key(goal)], original,
                       "the SwiftUI row id must survive an in-place minute correction")
    }
}
