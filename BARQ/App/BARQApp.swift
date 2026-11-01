import SwiftUI

@main
struct BARQApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.layoutDirection, store.lang == "en" ? .leftToRight : .rightToLeft)
                .environment(\.locale, Locale(identifier: store.lang == "en" ? "en" : "ar"))
                .preferredColorScheme(store.colorScheme)
                .tint(store.accent)
                .onAppear { LiveActivities.observePushToStart() }
        }
    }
}

enum AppTab: Hashable { case home, matches, ai, news, favorites, search }

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var tab: AppTab = .home
    @State private var deepLink = DeepLink.shared
    @State private var poller = InsightPoller()

    var body: some View {
        // Native iOS 26 floating Liquid Glass tab bar (system-provided material, not a blur imitation).
        TabView(selection: $tab) {
            Tab("الرئيسية", systemImage: "house", value: AppTab.home) { NavigationStack { HomeView() } }
            Tab("المباريات", systemImage: "soccerball", value: AppTab.matches) { NavigationStack { MatchesView() } }
            Tab("المحلل", systemImage: "brain.head.profile", value: AppTab.ai) { NavigationStack { AIView() } }
            Tab("الأخبار", systemImage: "newspaper", value: AppTab.news) { NavigationStack { NewsView() } }
            Tab("المفضلة", systemImage: "star", value: AppTab.favorites) { NavigationStack { FavoritesView() } }
            Tab(value: AppTab.search, role: .search) { NavigationStack { SearchView() } }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(item: Binding(get: { deepLink.fixtureId.map { IdBox(id: $0) } }, set: { deepLink.fixtureId = $0?.id })) { box in
            NavigationStack { MatchCenterView(fixtureId: box.id) }
        }
        .task { poller.start(store: store) }
        .onOpenURL { url in
            if url.host == "match", let id = Int(url.lastPathComponent) { deepLink.fixtureId = id }
        }
    }
}

struct IdBox: Identifiable { var id: Int }

/// Polls the server-side AI analyst feed while the app is open and raises local notifications.
/// Closed-app delivery = APNs from backend (see backend-addons/push.js).
@Observable final class InsightPoller {
    private var seen = Set<Int>()
    private var task: Task<Void, Never>?
    func start(store: AppStore) {
        guard task == nil else { return }
        task = Task { @MainActor in
            var first = true
            while !Task.isCancelled {
                if let feed: FeedResponse = try? await API.shared.get("/api/feed") {
                    store.notifications = feed.insights
                    for i in feed.insights where !seen.contains(i.id) {
                        seen.insert(i.id)
                        if !first && Notifier.allowed(i, density: store.alertDensity) { Notifier.post(i); store.unread += 1 }
                    }
                    first = false
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}
