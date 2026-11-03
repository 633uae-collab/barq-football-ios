import SwiftUI

@main
struct BARQApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var store: AppStore
    init() {
        _ = SplashDiag.processStart; SplashDiag.startHangWatch()
        SplashDiag.log.notice("APP init")
        Onboarding.resetIfRequested(); _store = State(initialValue: AppStore())
        SplashDiag.log.notice("APP store ready +\(Int(Date().timeIntervalSince(SplashDiag.processStart) * 1000), privacy: .public)ms")
    }

    var body: some Scene {
        WindowGroup {
            LaunchFlow { ScreenRouter() }
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
        // iPhone shows at most 5 tab items (incl. the search tab) before UIKit adds "More",
        // so News lives in Home's toolbar + its own screen; Search uses the native search-role tab.
        TabView(selection: $tab) {
            Tab("الرئيسية", systemImage: "house", value: AppTab.home) { NavigationStack { HomeView() } }
            Tab("المباريات", systemImage: "soccerball", value: AppTab.matches) { NavigationStack { MatchesView() } }
            Tab("المحلل", systemImage: "brain.head.profile", value: AppTab.ai) { NavigationStack { AIView() } }
            Tab("المفضلة", systemImage: "star", value: AppTab.favorites) { NavigationStack { FavoritesView() } }
            Tab(value: AppTab.search, role: .search) { NavigationStack { SearchView() } }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(item: Binding(get: { deepLink.fixtureId.map { IdBox(id: $0) } }, set: { deepLink.fixtureId = $0?.id })) { box in
            NavigationStack { MatchCenterView(fixtureId: box.id) }
        }
        .task {
            await LaunchGate.wait()
            poller.start(store: store)
            // Launch arguments used by CI screenshots: -startTab matches|ai|favorites|search, -openMatch <id>
            let d = UserDefaults.standard
            switch d.string(forKey: "startTab") { case "matches": tab = .matches; case "ai": tab = .ai; case "favorites": tab = .favorites; case "search": tab = .search; case "news": tab = .home; default: break }
            let m = d.integer(forKey: "openMatch"); if m > 0 { deepLink.fixtureId = m }
        }
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

/// CI/QA entry: `-screen <name> [-id N] [-q text]` opens any of the 17 screens directly with real backend data,
/// so the simulator job can screenshot every screen without UI scripting. Normal launches show RootView.
struct ScreenRouter: View {
    @Environment(AppStore.self) private var store
    @State private var poller = InsightPoller()
    @State private var monthOffset = 0
    @State private var preview: Fixture?
    @State private var laStatus = ""
    @State private var timelineMatch: MatchDetail?
    private let d = UserDefaults.standard
    var body: some View {
        if let screen = d.string(forKey: "screen") {
            NavigationStack { harness(screen).barqDestinations() }
                .task {
                    poller.start(store: store)
                    let fav = d.integer(forKey: "qaFavTeam")
                    if fav > 0, store.favTeams.isEmpty, let t: TeamResponse = try? await API.shared.get("/api/team/\(fav)"), let i = t.team {
                        store.favTeams = [TeamRef(id: i.id, name: i.name, logo: i.logo, winner: nil)]
                    }
                    if screen == "liveactivity" { await startActivity() }
                    if d.bool(forKey: "requestNotifs") { _ = await Notifier.requestPermission() }
                }
        } else {
            RootView()
        }
    }
    var id: Int { d.integer(forKey: "id") }

    @ViewBuilder func harness(_ s: String) -> some View {
        switch s {
        case "home": HomeView()
        case "matches": MatchesView()
        case "calendar": CalendarView()
        case "monthpicker": MonthPicker(offset: $monthOffset)
        case "match": MatchCenterView(fixtureId: id)
        case "preview":
            Group { if let f = preview { MatchPreview(f: f) } else { ProgressView() } }
                .task { preview = (try? await API.shared.get("/api/match/\(id)") as MatchDetail)?.match }
        case "timeline":
            ScrollView {
                if let m = timelineMatch {
                    VStack(spacing: 8) {
                        Text("\(m.match.home.name) \(m.match.scoreText) \(m.match.away.name)").font(.headline)
                        TimelineSection(d: m)
                    }.padding(.horizontal)
                } else { ProgressView() }
            }
            .screenBackground()
            .task { timelineMatch = try? await API.shared.get("/api/match/\(id)") }
        case "ai": AIView()
        case "favorites": FavoritesView()
        case "search": SearchView(initialQuery: d.string(forKey: "q") ?? "")
        case "news": NewsView()
        case "notifications": NotificationsView()
        case "settings": SettingsView()
        case "leagues": LeaguesView()
        case "league": LeagueCenterView(leagueId: id)
        case "club": ClubView(teamId: id)
        case "player": PlayerView(playerId: id)
        case "reorder": ReorderSectionsSheet()
        case "liveactivity":
            VStack(spacing: 12) {
                Image(systemName: "platter.filled.bottom.iphone").font(.largeTitle)
                Text(laStatus).font(.footnote.monospaced()).multilineTextAlignment(.center).accessibilityIdentifier("laStatus")
            }.padding()
        default: RootView()
        }
    }

    func startActivity() async {
        guard id > 0 else { laStatus = "no fixture id"; return }
        do {
            let aid = try await LiveActivities.startReal(fixtureId: id)
            laStatus = "LA_STARTED \(aid) enabled=\(LiveActivities.enabled)"
        } catch { laStatus = "LA_FAILED \(error.localizedDescription)" }
        print("BARQ_LA: \(laStatus)")
    }
}
