import Foundation
import Observation

/// Identity metadata only. The bundled directory is exported from FOTIQ's catalog
/// and every standings group in the seven onboarding leagues.
enum ClubDirectory {
    static let cacheKey = "onboarding.clubs.v1"
    static let leagueCacheKey = "onboarding.clubs.byLeague.v2"
    static let sources = [39, 140, 135, 78, 61, 307, 301]
    // These six crests are also bundled as image assets.
    static let bundled: [TeamRef] = [(40, "Liverpool"), (50, "Manchester City"), (33, "Manchester United"),
                                    (42, "Arsenal"), (49, "Chelsea"), (85, "Paris Saint Germain")].map {
        TeamRef(id: $0.0, name: $0.1, logo: "https://media.api-sports.io/football/teams/\($0.0).png")
    }

    struct Snapshot: Decodable {
        let clubs: [String: [TeamRef]]
        let competitions: [LeagueMeta]
    }
    static let snapshot: Snapshot = {
        guard let url = Bundle.main.url(forResource: "onboarding-directory", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let directory = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot(clubs: [:], competitions: [])
        }
        return directory
    }()

    static func unique(_ rows: [TeamRef]) -> [TeamRef] {
        var seen = Set<Int>()
        return rows.filter { $0.id > 0 && !$0.name.isEmpty && seen.insert($0.id).inserted }
    }
    static func cachedLeagues(_ defaults: UserDefaults) -> [String: [TeamRef]] {
        guard let data = defaults.data(forKey: leagueCacheKey) else { return [:] }
        return (try? JSONDecoder().decode([String: [TeamRef]].self, from: data)) ?? [:]
    }
    static func initial(_ defaults: UserDefaults) -> [TeamRef] {
        let cached = cachedLeagues(defaults)
        let clubs = sources.flatMap { id in cached[String(id)] ?? snapshot.clubs[String(id)] ?? [] }
        let legacy = defaults.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode([TeamRef].self, from: $0) } ?? []
        return unique((clubs.isEmpty ? bundled : clubs) + legacy)
    }

    private static let aliases = [40: "ليفربول", 50: "مانشستر سيتي", 33: "مانشستر يونايتد", 42: "أرسنال ارسنال",
        49: "تشيلسي", 85: "باريس سان جيرمان", 529: "برشلونة برشلونه بارسا", 541: "ريال مدريد", 530: "أتلتيكو مدريد",
        505: "إنتر ميلان انتر", 489: "ميلان", 496: "يوفنتوس", 157: "بايرن ميونخ", 165: "بوروسيا دورتموند",
        2932: "الهلال", 2939: "النصر السعودي", 2938: "الاتحاد", 2929: "الأهلي جدة",
        2865: "العين", 2870: "شباب الأهلي", 2871: "الجزيرة", 2874: "الشارقة", 2872: "الوصل", 2875: "الوحدة",
        10155: "النصر دبي", 2879: "عجمان", 4912: "خورفكان", 22321: "يونايتد دبي", 2876: "كلباء",
        2873: "الظفرة", 2877: "بني ياس", 2869: "حتا"]
    static func matching(_ teams: [TeamRef], query: String) -> [TeamRef] {
        teams.filter { $0.name.localizedCaseInsensitiveContains(query) || (aliases[$0.id] ?? "").contains(query) }
    }
}

@MainActor @Observable
final class ClubPickerModel {
    var popular: [TeamRef]
    var results: [TeamRef] = []
    var searching = false
    var loading = false
    var error: String?
    var searchError: String?
    private(set) var resultsTerm = ""
    private var searchRevision = 0
    private let defaults: UserDefaults
    static let sources = ClubDirectory.sources

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        popular = ClubDirectory.initial(defaults)
    }

    func loadPopular(fetch: @escaping (Int) async throws -> StandingsResponse = {
        try await API.shared.get("/api/standings/\($0)", maxAge: 3600, attempts: 1)
    }) async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        var refreshed: [String: [TeamRef]] = [:]
        leagues: for league in Self.sources {
            guard !Task.isCancelled else { return }
            do {
                let table = try await fetch(league)
                guard table.league?.id == league else { continue }
                let teams = ClubDirectory.unique(table.groups.flatMap { $0.map(\.team) })
                if !teams.isEmpty { refreshed[String(league)] = teams }
            } catch let failure as APIError {
                // A disconnected or rate-limited service cannot supply the remaining leagues.
                switch failure {
                case .offline, .temporary, .server("PLAN_LIMIT"): break leagues
                default: continue
                }
            } catch { continue }
        }
        guard !Task.isCancelled else { return }
        if !refreshed.isEmpty {
            let merged = ClubDirectory.cachedLeagues(defaults).merging(refreshed) { _, new in new }
            if let data = try? JSONEncoder().encode(merged) {
                defaults.set(data, forKey: ClubDirectory.leagueCacheKey)
                if refreshed.count == Self.sources.count { defaults.removeObject(forKey: ClubDirectory.cacheKey) }
                popular = ClubDirectory.initial(defaults)
            }
        }
        if refreshed.count < Self.sources.count {
            error = L.s("تعذر تحديث الأندية. تقدر تختار من القائمة المحفوظة أو تعيد المحاولة")
        }
    }

    func search(_ query: String, fetch: (String) async throws -> SearchResponse = {
        try await API.shared.get("/api/search?q=\($0)", maxAge: 300, attempts: 1)
    }) async {
        searchRevision += 1
        let revision = searchRevision
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        resultsTerm = term
        searching = false; searchError = nil
        results = ClubDirectory.matching(popular, query: term)
        guard term.count >= 3 else { return }
        searching = true
        defer { if revision == searchRevision { searching = false } }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: allowed) else { return }
        do {
            let response = try await fetch(encoded)
            guard !Task.isCancelled, revision == searchRevision else { return }
            let online = response.teams.map { TeamRef(id: $0.id, name: $0.name, logo: $0.logo) }
            results = ClubDirectory.unique(ClubDirectory.matching(popular, query: term) + online)
        } catch {
            guard !Task.isCancelled, revision == searchRevision else { return }
            searchError = L.s("تعذر البحث عبر الإنترنت. النتائج الظاهرة من القائمة المحفوظة")
        }
    }
}
