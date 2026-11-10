import SwiftUI
import UIKit

/// Launch-owned presentation cache. The API client, live refresh rules and
/// destination components remain unchanged. Never fabricate fixtures for startup.
struct LaunchHomeSnapshot: Codable {
    var scope: String
    var savedAt: Date
    var today: [Fixture]
    var tomorrow: [Fixture]
    var stars: [StarPlayer]?
    var lineupsReady: Set<Int>
    func usable(scope: String, now: Date = Date()) -> Bool {
        // A short-lived warm-start cache is not an offline source of live scores.
        self.scope == scope && (0...120).contains(now.timeIntervalSince(savedAt))
    }
}

@MainActor enum LaunchHomePreparation {
    static var snapshot: LaunchHomeSnapshot?
    static var scope: String {
        UserDefaults.standard.string(forKey: "apiOverride")
            ?? (Bundle.main.object(forInfoDictionaryKey: "FOTIQAPIBase") as? String)
            ?? API.configURL
    }
}

actor LaunchHomeCache {
    static let shared = LaunchHomeCache()
    private var location: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rider-home-v1.json")
    }
    func restore(scope: String) -> LaunchHomeSnapshot? {
        guard let data = try? Data(contentsOf: location), data.count < 2_000_000,
              let snapshot = try? JSONDecoder().decode(LaunchHomeSnapshot.self, from: data),
              snapshot.usable(scope: scope) else { return nil }
        return snapshot
    }
    func save(_ snapshot: LaunchHomeSnapshot) {
        // Actor serialization prevents older, partial snapshots overwriting newer
        // ones. Only responses the existing Home loader actually received are saved.
        if let previous = restore(scope: snapshot.scope), previous.savedAt > snapshot.savedAt { return }
        guard let data = try? JSONEncoder().encode(snapshot), data.count < 2_000_000 else { return }
        try? data.write(to: location, options: .atomic)
    }
    func prepareCachedImages(_ snapshot: LaunchHomeSnapshot) {
        var addresses = (snapshot.today + snapshot.tomorrow).prefix(24).flatMap { [$0.home.logo, $0.away.logo, $0.league.logo] }
        addresses += (snapshot.stars ?? []).prefix(3).map(\.photo)
        var seen = Set<String>()
        for case let address? in addresses where seen.insert(address).inserted {
            guard let url = URL(string: address),
                  ImageStore.shared.mem.object(forKey: address as NSString) == nil,
                  let response = ImageStore.shared.session.configuration.urlCache?.cachedResponse(for: URLRequest(url: url)),
                  let image = UIImage(data: response.data) else { continue }
            ImageStore.shared.mem.setObject(image.preparingForDisplay() ?? image, forKey: address as NSString)
        }
    }
}

/// Same native cards and dimensions while no valid local response exists. Text
/// is explicitly redacted; a placeholder must never assert invented match data.
struct LaunchHomeLoadingSection: View {
    let key: String
    var body: some View {
        Group {
            switch key {
            case "carousel": FavoritesHero(matches: [], lineupsReady: []) {}
            case "stars": StarsCard(players: nil, active: false)
            case "upcoming", "today":
                SectionHeader(title: key == "upcoming" ? "المباريات القادمة" : "مباريات اليوم", symbol: "calendar")
                GlassCard {
                    HStack {
                        Image(systemName: "shield").font(.largeTitle)
                        Spacer(); Text("جاري تحميل المباريات"); Spacer()
                        Image(systemName: "shield").font(.largeTitle)
                    }.frame(height: 52)
                }
            default: EmptyView()
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("جاري تحميل المباريات")
        .accessibilityIdentifier("launch-home-placeholder-" + key)
    }
}
