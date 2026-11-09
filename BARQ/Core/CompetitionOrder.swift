import Foundation

/// IDs verified against the deployed API-Football catalog, 7 November 2026.
/// Priority affects display only; saved IDs, provider logos and club ordering are untouched.
enum CompetitionOrder {
    static let leagues = [39, 140, 135, 78, 61, 307, 301, 94, 88, 203]
    static let cups = [1, 2, 17, 3, 7, 9, 4, 25, 15, 45]
    static func sorted(_ catalog: [LeagueMeta], kind: String) -> [LeagueMeta] {
        let priority = kind == "Cup" ? cups : leagues
        var seen = Set<Int>()
        let all = catalog.filter { ($0.type ?? "League") == kind && seen.insert($0.id).inserted }
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return priority.compactMap { byID[$0] } + all.filter { !priority.contains($0.id) }
    }
}
