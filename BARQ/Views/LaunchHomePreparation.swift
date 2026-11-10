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
    func visibleImageAddresses(favorites: HomeFeed.Favorites, now: Date) -> [String] {
        let all = today + tomorrow
        // Response order is not Home's display order. Prepare the actual hero,
        // first upcoming rows and first important fixtures, including star badges.
        let fixtures = HomeFeed.dedupe(Array(HomeFeed.hero(all, favorites: favorites, now: now).prefix(6))
            + HomeFeed.upcoming(all, now: now, limit: 6)
            + Array(MatchSort.byImportance(today).prefix(6)))
        var addresses = fixtures.flatMap { [$0.home.logo, $0.away.logo, $0.league.logo] }
        addresses += (stars ?? []).prefix(3).flatMap { [$0.photo, $0.team.logo] }
        var seen = Set<String>()
        return addresses.compactMap { $0 }.filter { seen.insert($0).inserted }
    }
    func usable(scope: String, now: Date = Date()) -> Bool {
        // A short-lived warm-start cache is not an offline source of live scores.
        self.scope == scope && (0...120).contains(now.timeIntervalSince(savedAt))
    }
}

@MainActor enum LaunchHomePreparation {
    static var snapshot: LaunchHomeSnapshot?
    static var images: [String: UIImage] = [:]
    static var scope: String {
        UserDefaults.standard.string(forKey: "apiOverride")
            ?? (Bundle.main.object(forInfoDictionaryKey: "FOTIQAPIBase") as? String)
            ?? API.configURL
    }
}

actor LaunchHomeCache {
    static let shared = LaunchHomeCache()
    private let imageDisk = LaunchImageDiskCache(directory: FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("rider-images-v1", isDirectory: true))
    func saveImage(_ data: Data, address: String) {
        try? imageDisk.save(data, for: address)
    }
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
    func prepareCachedImages(_ addresses: [String]) -> [String: UIImage] {
        var prepared: [String: UIImage] = [:]
        var diskHits = 0, bundledHits = 0
        // Original provider PNGs for the six identities already bundled by
        // ClubDirectory. Fresh installation can reveal their real logos even
        // without a prior disk cache or any internet connection.
        let bundled = Dictionary(uniqueKeysWithValues: [40, 50, 33, 42, 49, 85].map {
            ("https://media.api-sports.io/football/teams/\($0).png", "LaunchClub\($0)")
        })
        for address in addresses {
            if let image = ImageStore.shared.mem.object(forKey: address as NSString) {
                prepared[address] = image
                continue
            }
            if let name = bundled[address], let image = UIImage(named: name) {
                let decoded = image.preparingForDisplay() ?? image
                prepared[address] = decoded
                ImageStore.shared.mem.setObject(decoded, forKey: address as NSString)
                bundledHits += 1
                continue
            }
            guard let url = URL(string: address) else { continue }
            let request = URLRequest(url: url)
            // Older StarRow used AsyncImage's shared cache rather than ImageStore.
            // Both lookups are disk/memory only; neither can start a network request.
            let response = ImageStore.shared.session.configuration.urlCache?.cachedResponse(for: request)
                ?? URLCache.shared.cachedResponse(for: request)
            let durableData = imageDisk.load(address)
            guard let data = durableData ?? response?.data, let image = UIImage(data: data) else { continue }
            if durableData != nil { diskHits += 1 }
            let decoded = image.preparingForDisplay() ?? image
            ImageStore.shared.mem.setObject(decoded, forKey: address as NSString)
            prepared[address] = decoded
        }
        SplashDiag.log.notice("IMAGES requested=\(addresses.count, privacy: .public) prepared=\(prepared.count, privacy: .public) durableHits=\(diskHits, privacy: .public) bundledHits=\(bundledHits, privacy: .public)")
        return prepared
    }
}

private struct LaunchPreparedImagesKey: EnvironmentKey {
    static let defaultValue: [String: UIImage] = [:]
}
extension EnvironmentValues {
    var launchPreparedImages: [String: UIImage] {
        get { self[LaunchPreparedImagesKey.self] }
        set { self[LaunchPreparedImagesKey.self] = newValue }
    }
}

/// First layout reads an immutable, already-decoded image. A cache miss keeps
/// the original placeholder and waits for launch before publishing a download.
/// Uses the same photo crop and placeholder as StarRow's former AsyncImage.
struct LaunchPreparedPlayerPhoto: View {
    let url: String?
    @Environment(\.launchPreparedImages) private var prepared
    @State private var downloaded: UIImage?
    var body: some View {
        Group {
            if let image = downloaded ?? prepared[url ?? ""] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.fill").foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            guard prepared[url ?? ""] == nil else { return }
            await LaunchGate.wait()
            guard !Task.isCancelled, let url, let address = URL(string: url) else { return }
            let image = await ImageStore.shared.image(address)
            guard !Task.isCancelled else { return }
            downloaded = image
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

