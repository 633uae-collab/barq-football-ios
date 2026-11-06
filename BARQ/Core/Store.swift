import SwiftUI
import Observation

enum ThemeMode: String, CaseIterable, Codable { case system, dark, light }

/// User preferences, persisted locally and synced to backend /api/prefs/:device (same as web app).
@Observable
final class AppStore {
    static let accents: [(String, Color)] = [("fotiq", Color("BrandGreen")), ("blue", .blue), ("cyan", .cyan), ("green", .green), ("orange", .orange), ("pink", .pink), ("purple", .purple)]

    var favTeams: [TeamRef] { didSet { save() } }
    var favLeagues: [Int] { didSet { save() } }
    var savedMatches: [Int] { didSet { save() } }
    var homeSections: [String] { didSet { save() } }
    var mutedTeams: [Int] { didSet { save() } }
    var theme: ThemeMode { didSet { save() } }
    var accentKey: String { didSet { save() } }
    var lang: String { didSet { AppLanguage.apply(lang); save() } }
    var tz: String { didSet { save() } }
    var alertDensity: Int { didSet { save() } }   // 0 = critical only, 1 = balanced, 2 = all
    var notifications: [Insight] = []
    var unread = 0

    let deviceId: String
    private let defaults: UserDefaults
    private let syncEnabled: Bool
    private let outbox: PreferencesOutbox

    static let defaultSections = ["carousel", "stars", "upcoming"]
    /// Pre-v8 Home sections (kept for reference; their views still exist in HomeView).
    static let legacySections = ["carousel", "ticker", "ai", "favorites", "today"]

    init(defaults d: UserDefaults = .standard, syncEnabled: Bool = true) {
        defaults = d
        self.syncEnabled = syncEnabled && d === UserDefaults.standard
        outbox = d === UserDefaults.standard ? .shared : PreferencesOutbox(defaults: d)
        if let id = d.string(forKey: "deviceId") { deviceId = id } else { let id = UUID().uuidString; d.set(id, forKey: "deviceId"); deviceId = id }
        func load<T: Decodable>(_ k: String, _ def: T) -> T {
            guard let data = d.data(forKey: k) else { return def }
            if let v = try? JSONDecoder().decode(T.self, from: data) { return v }
            if let backup = d.data(forKey: k + ".backup"), let v = try? JSONDecoder().decode(T.self, from: backup) { return v }
            return def
        }
        favTeams = load("favTeams", [])
        favLeagues = load("favLeagues", [301, 307, 39, 140, 2])
        savedMatches = load("savedMatches", [])
        // v8 Home layout (favorites hero / FOTIQ STARS / upcoming): migrate once from the old section list.
        if d.bool(forKey: "homeLayoutV8") { homeSections = load("homeSections", Self.defaultSections) }
        else {
            let existing: [String] = load("homeSections", Self.defaultSections)
            homeSections = existing == Self.legacySections ? Self.defaultSections : existing
            d.set(try? JSONEncoder().encode(homeSections), forKey: "homeSections"); d.set(true, forKey: "homeLayoutV8")
        }
        mutedTeams = load("mutedTeams", [])
        theme = ThemeMode(rawValue: d.string(forKey: "theme") ?? "") ?? .dark
        accentKey = d.string(forKey: "accent") ?? "fotiq"
        lang = d.string(forKey: "lang") ?? "ar"
        tz = d.string(forKey: "tz") ?? "Asia/Dubai"
        alertDensity = d.object(forKey: "alertDensity") as? Int ?? 1
        AppLanguage.apply(lang)
    }

    var accent: Color { Self.accents.first { $0.0 == accentKey }?.1 ?? Color("BrandGreen") }
    var colorScheme: ColorScheme? { theme == .system ? nil : (theme == .dark ? .dark : .light) }

    func isFav(team id: Int) -> Bool { favTeams.contains { $0.id == id } }
    func toggleFav(_ t: TeamRef) {
        if let i = favTeams.firstIndex(where: { $0.id == t.id }) { favTeams.remove(at: i) }
        else { favTeams.append(TeamRef(id: t.id, name: t.name, logo: t.logo)); Haptics.favoriteAdded() }
    }
    func toggleLeague(_ id: Int) {
        if let i = favLeagues.firstIndex(of: id) { favLeagues.remove(at: i) } else { favLeagues.append(id); Haptics.favoriteAdded() }
    }
    func toggleSaved(_ id: Int) {
        if let i = savedMatches.firstIndex(of: id) { savedMatches.remove(at: i) } else { savedMatches.append(id); Haptics.favoriteAdded() }
    }
    func toggleMuted(_ id: Int) {
        if let i = mutedTeams.firstIndex(of: id) { mutedTeams.remove(at: i) } else { mutedTeams.append(id) }
    }

    private func save() {
        let d = defaults, e = JSONEncoder()
        func persist<T: Encodable>(_ value: T, _ key: String) {
            guard let data = try? e.encode(value) else { return }
            d.set(data, forKey: key + ".backup")
            d.set(data, forKey: key)
        }
        persist(favTeams, "favTeams")
        persist(favLeagues, "favLeagues")
        persist(savedMatches, "savedMatches")
        persist(homeSections, "homeSections")
        persist(mutedTeams, "mutedTeams")
        d.set(theme.rawValue, forKey: "theme")
        d.set(accentKey, forKey: "accent")
        d.set(alertDensity, forKey: "alertDensity")
        d.set(lang, forKey: "lang")
        d.set(tz, forKey: "tz")
        let snapshot = PrefsPayload(favTeams: favTeams.map(\.id), favLeagues: favLeagues, saved: savedMatches, muted: mutedTeams, level: alertDensity)
        outbox.enqueue(device: deviceId, payload: snapshot)
        if syncEnabled { Task { await PreferencesSync.shared.flush() } }
    }
}

/// Matches backend catalog.js prefs (favTeams/saved/muted/level) used by the server push system (notify.js).
struct PrefsPayload: Codable { var favTeams: [Int]; var favLeagues: [Int]; var saved: [Int]; var muted: [Int] = []; var level: Int = 1 }

/// Shared favorite haptic: light impact only when a favorite is ADDED (removing is silent). Needs a real iPhone to feel.
enum Haptics {
    static func favoriteAdded() {
        Task { @MainActor in let g = UIImpactFeedbackGenerator(style: .light); g.prepare(); g.impactOccurred() }
    }
}
