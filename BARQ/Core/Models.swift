import Foundation

/// Any JSON scalar (API-Football mixes ints, strings, "45%" and null).
enum JSONValue: Codable, Hashable {
    case int(Int), double(Double), string(String), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else { self = .null }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    var text: String {
        switch self {
        case .int(let v): return String(v)
        case .double(let v): return String(format: "%.2f", v)
        case .string(let v): return v
        case .bool(let v): return v ? "1" : "0"
        case .null: return "0"
        }
    }
    var number: Double {
        switch self {
        case .int(let v): return Double(v)
        case .double(let v): return v
        case .string(let v): return Double(v.replacingOccurrences(of: "%", with: "")) ?? 0
        default: return 0
        }
    }
}

struct TeamRef: Codable, Hashable, Identifiable {
    var id: Int
    var name: String
    var logo: String?
    var winner: Bool?
}

struct FixtureStatus: Codable, Hashable {
    var long: String?
    var short: String
    var elapsed: Int?
    var extra: Int?
}

struct LeagueRef: Codable, Hashable {
    var id: Int
    var name: String
    var logo: String?
    var round: String?
    var country: String?
    var season: Int?
}

struct Goals: Codable, Hashable { var home: Int?; var away: Int? }

struct Fixture: Codable, Hashable, Identifiable {
    var id: Int
    var date: String
    var ts: Int
    var status: FixtureStatus
    var venue: String?
    var referee: String?
    var league: LeagueRef
    var home: TeamRef
    var away: TeamRef
    var goals: Goals
    var imp: Double?

    static let liveCodes: Set<String> = ["1H", "HT", "2H", "ET", "BT", "P", "LIVE", "INT", "SUSP"]
    static let doneCodes: Set<String> = ["FT", "AET", "PEN", "AWD", "WO"]
    var isLive: Bool { Self.liveCodes.contains(status.short) }
    var isDone: Bool { Self.doneCodes.contains(status.short) }
    var isUpcoming: Bool { !isLive && !isDone }
    var kickoff: Date { Date(timeIntervalSince1970: TimeInterval(ts)) }
    var scoreText: String { "\(goals.home ?? 0) - \(goals.away ?? 0)" }
    var importance: Double { imp ?? 0 }
}

/// Deterministic ordering: live first, then importance desc, then kickoff, then id.
enum MatchSort {
    static func byImportance(_ list: [Fixture]) -> [Fixture] {
        list.sorted { a, b in
            if a.isLive != b.isLive { return a.isLive }
            if a.importance != b.importance { return a.importance > b.importance }
            if a.ts != b.ts { return a.ts < b.ts }
            return a.id < b.id
        }
    }
    /// Top N for the home carousel: today's best, filled with tomorrow's if needed.
    static func topN(today: [Fixture], tomorrow: [Fixture], n: Int = 5) -> [Fixture] {
        let t = byImportance(today.filter { !$0.isDone || $0.isLive })
        let fallbackToday = byImportance(today)
        var out = Array(t.prefix(n))
        if out.count < n { out += fallbackToday.filter { !out.contains($0) }.prefix(n - out.count) }
        if out.count < n { out += byImportance(tomorrow).prefix(n - out.count) }
        return out
    }
}

struct LeagueMeta: Codable, Hashable, Identifiable {
    var id: Int
    var name: String
    var ar: String?
    var logo: String?
    var country: String?
    var countryAr: String?
    var continent: String?
    var group: String?
    var season: Int?
    var type: String?
    var active: Bool?
    var displayName: String { (ar?.isEmpty == false ? ar : nil) ?? name }
}

struct FixturesResponse: Codable {
    var date: String
    var fetchedAt: Double?
    var stale: Bool?
    var leagues: [String: LeagueMeta]?
    var fixtures: [Fixture]
}

struct CatalogResponse: Codable {
    var total: Int?
    var order: [Int]?
    var continents: [String: String]?
    var leagues: [LeagueMeta]
}

struct MetaResponse: Codable { var usedToday: Int; var cap: Int; var today: String; var tz: String }

// MARK: Match center
struct EventTime: Codable, Hashable { var elapsed: Int?; var extra: Int? }
struct NamedRef: Codable, Hashable { var id: Int?; var name: String? }
struct MatchEvent: Codable, Hashable {
    var time: EventTime
    var team: TeamRef
    var player: NamedRef?
    var assist: NamedRef?
    var type: String
    var detail: String?
}
struct LineupPlayer: Codable, Hashable {
    struct P: Codable, Hashable { var id: Int?; var name: String; var number: Int?; var pos: String?; var grid: String? }
    var player: P
}
struct Lineup: Codable, Hashable {
    var team: TeamRef
    var formation: String?
    var startXI: [LineupPlayer]
    var substitutes: [LineupPlayer]?
    var coach: NamedRef?
}
struct StatItem: Codable, Hashable { var type: String; var value: JSONValue? }
struct TeamStats: Codable, Hashable { var team: TeamRef; var statistics: [StatItem] }

struct MatchDetail: Codable {
    var fetchedAt: Double?
    var stale: Bool?
    var match: Fixture
    var events: [MatchEvent]
    var lineups: [Lineup]
    var statistics: [TeamStats]
}

struct Prediction: Codable {
    struct Pct: Codable { var home: String?; var draw: String?; var away: String? }
    struct PTeam: Codable { var id: Int; var name: String; var logo: String?; var form: String? }
    struct PTeams: Codable { var home: PTeam; var away: PTeam }
    struct Pair: Codable { var home: String?; var away: String? }
    var fetchedAt: Double?
    var percent: Pct?
    var advice: String?
    var comparison: [String: Pair]?
    var teams: PTeams?
}

struct FixtureList: Codable { var fetchedAt: Double?; var fixtures: [Fixture] }

// MARK: Leagues
struct StandingRow: Codable, Hashable, Identifiable {
    struct Record: Codable, Hashable {
        struct G: Codable, Hashable { var `for`: Int?; var against: Int? }
        var played: Int?; var win: Int?; var draw: Int?; var lose: Int?; var goals: G?
    }
    var rank: Int
    var team: TeamRef
    var points: Int
    var goalsDiff: Int?
    var group: String?
    var form: String?
    var description: String?
    var all: Record?
    var id: Int { team.id }
}
struct StandingsResponse: Codable { var league: LeagueMeta?; var groups: [[StandingRow]]; var note: String? }

struct TopPlayer: Codable, Hashable, Identifiable {
    var id: Int; var name: String; var photo: String?; var team: TeamRef?
    var goals: Int?; var assists: Int?; var apps: Int?
}
struct TopPlayersResponse: Codable { var players: [TopPlayer]; var note: String? }

struct LeagueFixtures: Codable { var league: LeagueMeta?; var next: [Fixture]; var last: [Fixture] }

// MARK: Team / Player
struct TeamInfo: Codable, Hashable { var id: Int; var name: String; var logo: String?; var country: String?; var founded: Int? }
struct VenueInfo: Codable, Hashable { var name: String?; var city: String?; var capacity: Int?; var image: String? }
struct SquadPlayer: Codable, Hashable, Identifiable { var id: Int; var name: String; var photo: String?; var number: Int?; var pos: String?; var age: Int? }
struct Transfer: Codable, Hashable {
    var player: NamedRef; var date: String; var type: String?; var `in`: TeamRef; var out: TeamRef
}
struct TeamResponse: Codable {
    var team: TeamInfo?; var venue: VenueInfo?
    var next: [Fixture]?; var last: [Fixture]?; var squad: [SquadPlayer]?; var transfers: [Transfer]?
}
struct PlayerInfo: Codable, Hashable {
    var id: Int; var name: String; var firstname: String?; var lastname: String?; var age: Int?
    var nationality: String?; var height: String?; var weight: String?; var photo: String?
}
struct PlayerSeasonStat: Codable, Hashable {
    var team: TeamRef; var league: LeagueRef
    var apps: Int?; var minutes: Int?; var rating: String?; var pos: String?
    var goals: Int; var assists: Int; var shots: Int; var sot: Int; var passes: Int; var keyPasses: Int
    var dribbles: Int; var tackles: Int; var yellow: Int; var red: Int
}
struct PlayerResponse: Codable { var player: PlayerInfo?; var stats: [PlayerSeasonStat]? }

// MARK: Search
struct SearchResponse: Codable {
    struct L: Codable, Hashable, Identifiable { var id: Int; var name: String; var en: String?; var logo: String? }
    struct T: Codable, Hashable, Identifiable { var id: Int; var name: String; var logo: String?; var country: String? }
    struct P: Codable, Hashable, Identifiable { var id: Int; var name: String; var photo: String?; var nationality: String?; var position: String? }
    var q: String
    var translated: String?
    var leagues: [L]; var teams: [T]; var players: [P]; var matches: [Fixture]
    var notes: [String]?
}

// MARK: AI analyst
struct InsightMatch: Codable, Hashable { var home: String; var away: String; var homeLogo: String?; var awayLogo: String?; var league: String?; var score: String? }
struct Insight: Codable, Hashable, Identifiable {
    var id: Int; var fixture: Int; var minute: Int; var type: String; var level: String
    var team: String?; var title: String; var body: String
    var nums: [String: JSONValue]?
    var at: Double
    var match: InsightMatch?
    var date: Date { Date(timeIntervalSince1970: at / 1000) }
    /// SF Symbol per insight type (no emoji anywhere).
    var symbol: String {
        switch type {
        case "pressure": return "flame"
        case "shift": return "arrow.left.arrow.right"
        case "possession": return "circle.lefthalf.filled"
        case "red": return "rectangle.portrait.fill"
        case "ht": return "pause.circle"
        case "ft": return "flag.checkered"
        default: return "brain.head.profile"
        }
    }
}
struct FeedResponse: Codable { var tracking: Int?; var insights: [Insight] }
struct Momentum: Codable, Hashable { var home: Double?; var away: Double? }
struct InsightsResponse: Codable {
    var status: String; var minute: Int?; var lastAt: Double?
    var insights: [Insight]
}
