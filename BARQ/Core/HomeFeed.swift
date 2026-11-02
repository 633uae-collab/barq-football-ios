import Foundation

/// Pure, clock-injectable rules for the Home page (favorites hero, upcoming list, stars rotation).
/// All inputs are real backend data; tests inject fixtures + a fixed `now`.
enum HomeFeed {
    /// Statuses that mean "not started yet" (API-SPORTS). PST/CANC/ABD are excluded on purpose.
    static let notStarted: Set<String> = ["NS", "TBD"]
    static let heroWindow: TimeInterval = 3600

    struct Favorites: Equatable {
        var matches: Set<Int> = []
        var teams: Set<Int> = []
        var leagues: Set<Int> = []
        func contains(_ f: Fixture) -> Bool {
            matches.contains(f.id) || teams.contains(f.home.id) || teams.contains(f.away.id) || leagues.contains(f.league.id)
        }
    }

    /// Live (incl. HT, ET, BT, penalties), or not started and kicking off within 60 minutes.
    /// A match still "NS" shortly after its scheduled time (late status update) stays for up to 2 h.
    static func heroEligible(_ f: Fixture, now: Date) -> Bool {
        if f.isLive { return true }
        guard notStarted.contains(f.status.short) else { return false }
        let left = f.kickoff.timeIntervalSince(now)
        return left <= heroWindow && left > -7200
    }

    /// Stable order: live first, then soonest kickoff, then fixture id.
    static func hero(_ all: [Fixture], favorites: Favorites, now: Date) -> [Fixture] {
        dedupe(all).filter { favorites.contains($0) && heroEligible($0, now: now) }.sorted { a, b in
            if a.isLive != b.isLive { return a.isLive }
            if a.ts != b.ts { return a.ts < b.ts }
            return a.id < b.id
        }
    }

    /// Upcoming only (not started, kickoff in the future), soonest first, no duplicates.
    static func upcoming(_ all: [Fixture], now: Date, limit: Int = 20) -> [Fixture] {
        Array(dedupe(all).filter { notStarted.contains($0.status.short) && $0.kickoff > now }
            .sorted { $0.ts != $1.ts ? $0.ts < $1.ts : $0.id < $1.id }.prefix(limit))
    }

    /// Keep what the user is looking at across refreshes; fall back to the first item only if it disappeared.
    static func keepSelection(_ current: Int?, in ids: [Int]) -> Int? {
        if let c = current, ids.contains(c) { return c }
        return ids.first
    }

    static func nextStar(_ current: Int?, in ids: [Int]) -> Int? {
        guard !ids.isEmpty else { return nil }
        guard let c = current, let i = ids.firstIndex(of: c) else { return ids.first }
        return ids[(i + 1) % ids.count]
    }

    /// "MM:SS" under an hour, "H:MM:SS" otherwise; "00:00" once kickoff time has passed.
    static func countdown(to kickoff: Date, now: Date) -> String {
        let s = max(0, Int(kickoff.timeIntervalSince(now).rounded(.up)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    static func dedupe(_ list: [Fixture]) -> [Fixture] {
        var seen = Set<Int>(); return list.filter { seen.insert($0.id).inserted }
    }

    /// Kickoff time always in UAE time (Asia/Dubai), as the spec requires.
    static let uae = TimeZone(identifier: "Asia/Dubai")!
    static func uaeTime(_ d: Date) -> String {
        let f = DateFormatter(); f.timeZone = uae; f.locale = Fmt.locale; f.dateFormat = "h:mm a"; return f.string(from: d)
    }
    static func uaeDate(_ d: Date) -> String {
        let f = DateFormatter(); f.timeZone = uae; f.locale = Fmt.locale; f.dateFormat = "EEE d MMM"; return f.string(from: d)
    }
}

/// /api/stars — players backed by real fixture stats (goals, assists or rating >= 7.5).
struct StarPlayer: Codable, Hashable, Identifiable {
    var id: Int
    var name: String
    var photo: String?
    var team: TeamRef
    var fixture: Int
    var league: String?
    var live: Bool?
    var rating: Double?
    var goals: Int
    var assists: Int
    var minutes: Int?
}
struct StarsResponse: Codable { var date: String; var fetchedAt: Double?; var stale: Bool?; var players: [StarPlayer] }
