import Foundation
import Observation

/// Only club identity metadata is bundled, never fixtures/results. IDs and names come from
/// BARQTests/Payloads/real-team-40.json and real-player-1100.json (recorded API-Football responses).
enum ClubDirectory {
    static let cacheKey = "onboarding.clubs.v1"
    static let bundled: [TeamRef] = [(40, "Liverpool"), (50, "Manchester City"), (33, "Manchester United"),
                                    (42, "Arsenal"), (49, "Chelsea"), (85, "Paris Saint Germain")].map {
        TeamRef(id: $0.0, name: $0.1, logo: "https://media.api-sports.io/football/teams/\($0.0).png")
    }
    static func initial(_ defaults: UserDefaults) -> [TeamRef] {
        guard let data = defaults.data(forKey: cacheKey), let teams = try? JSONDecoder().decode([TeamRef].self, from: data), !teams.isEmpty else { return bundled }
        return teams
    }
    static func matching(_ teams: [TeamRef], query: String) -> [TeamRef] {
        let aliases = [40: "ليفربول", 50: "مانشستر سيتي", 33: "مانشستر يونايتد", 42: "أرسنال ارسنال", 49: "تشيلسي", 85: "باريس سان جيرمان"]
        return teams.filter { $0.name.localizedCaseInsensitiveContains(query) || (aliases[$0.id] ?? "").contains(query) }
    }
}

@MainActor @Observable
final class ClubPickerModel {
    var popular: [TeamRef]
    var results: [TeamRef] = []
    var loading = false
    var searching = false
    var error: String?
    var searchError: String?
    private var searchRevision = 0
    private let defaults: UserDefaults
    static let sources = [39, 140, 135, 78, 61, 307, 301]

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
        let lists = await withTaskGroup(of: (Int, [TeamRef]).self) { group in
            for (index, league) in Self.sources.enumerated() {
                group.addTask { (index, ((try? await fetch(league))?.groups.first ?? []).prefix(8).map(\.team)) }
            }
            var out: [(Int, [TeamRef])] = []
            for await result in group { out.append(result) }
            return out
        }
        guard !Task.isCancelled else { return }
        var seen = Set<Int>()
        let teams = lists.sorted { $0.0 < $1.0 }.flatMap { $0.1 }.filter { seen.insert($0.id).inserted }
        guard !teams.isEmpty else {
            error = L.s("تعذر تحديث الأندية. تقدر تختار من القائمة المحفوظة أو تعيد المحاولة")
            return
        }
        popular = teams
        defaults.set(try? JSONEncoder().encode(teams), forKey: ClubDirectory.cacheKey)
    }

    func search(_ query: String, fetch: (String) async throws -> SearchResponse = {
        try await API.shared.get("/api/search?q=\($0)", maxAge: 300, attempts: 1)
    }) async {
        searchRevision += 1
        let revision = searchRevision
        searching = false; searchError = nil
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        results = ClubDirectory.matching(popular, query: term)
        guard term.count >= 2 else { return }
        searching = true
        defer { if revision == searchRevision { searching = false } }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: allowed) else { return }
        do {
            let response = try await fetch(encoded)
            guard !Task.isCancelled, revision == searchRevision else { return }
            results = response.teams.map { TeamRef(id: $0.id, name: $0.name, logo: $0.logo) }
        } catch {
            guard !Task.isCancelled, revision == searchRevision else { return }
            searchError = L.s("تعذر البحث عبر الإنترنت. النتائج الظاهرة من القائمة المحفوظة")
        }
    }
}
