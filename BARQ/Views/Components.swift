import SwiftUI

/// Remote image with in-memory cache, shared disk URLCache and retry (AsyncImage gives up on the first
/// failure/cancellation, which left placeholder shields in fast-scrolling carousels).
final class ImageStore {
    static let shared = ImageStore()
    let mem = NSCache<NSString, UIImage>()
    let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 24 << 20, diskCapacity: 200 << 20)
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.timeoutIntervalForRequest = 15
        c.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: c)
    }()
    func image(_ url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let i = mem.object(forKey: key) { return i }
        for attempt in 0..<3 {
            if let (d, r) = try? await session.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200, let img = UIImage(data: d) {
                mem.setObject(img, forKey: key); return img
            }
            if Task.isCancelled { return nil }
            try? await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
        }
        return nil
    }
}

struct RemoteImage: View {
    let url: String?
    var fallback: String = "shield"
    var size: CGFloat = 32
    var circle = false
    @State private var img: UIImage?
    var body: some View {
        Group {
            if let img { Image(uiImage: img).resizable().scaledToFit().transition(.opacity) }
            else { Image(systemName: fallback).resizable().scaledToFit().foregroundStyle(.secondary).padding(size * 0.18) }
        }
        .frame(width: size, height: size)
        .clipShape(circle ? AnyShape(Circle()) : AnyShape(Rectangle()))
        .task(id: url) {
            guard let s = url, let u = URL(string: s) else { img = nil; return }
            if let c = ImageStore.shared.mem.object(forKey: s as NSString) { img = c; return }
            let r = await ImageStore.shared.image(u)
            withAnimation(.easeOut(duration: 0.2)) { img = r }
        }
    }
}

/// Real iOS 26 Liquid Glass card.
struct GlassCard<Content: View>: View {
    var radius: CGFloat = 22
    var interactive = false
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(interactive ? .regular.interactive() : .regular, in: .rect(cornerRadius: radius))
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    let symbol: String
    var body: some View {
        Label(title, systemImage: symbol).font(.title3.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
    }
}

struct LivePill: View {
    var minute: Int?
    var extra: Int? = nil
    var status: String? = nil
    var label: String {
        if status == "HT" { return String(localized: "استراحة") }
        guard let m = minute else { return "LIVE" }
        return extra.map { "\(m)+\($0)'" } ?? "\(m)'"
    }
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(.red).frame(width: 7, height: 7).opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(), value: pulse)
            Text(label).font(.caption.bold()).monospacedDigit()
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .glassEffect(.regular.tint(.red.opacity(0.25)), in: .capsule)
        .onAppear { pulse = true }
    }
}

struct StatusBadge: View {
    let f: Fixture
    var body: some View {
        if f.isLive { LivePill(minute: f.status.elapsed, extra: f.status.extra, status: f.status.short) }
        else if f.isDone { Label("انتهت", systemImage: "flag.checkered").font(.caption).foregroundStyle(.secondary) }
        else { Label(Fmt.time(f.kickoff), systemImage: "clock").font(.caption).foregroundStyle(.secondary) }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey? = nil
    var body: some View {
        ContentUnavailableView { Label(title, systemImage: symbol) } description: { if let m = message { Text(m) } }
    }
}

struct LoadState<T, C: View>: View {
    let value: T?
    let error: String?
    var retry: (() async -> Void)? = nil
    @ViewBuilder var content: (T) -> C
    var body: some View {
        if let v = value { content(v) }
        else if let e = error {
            ContentUnavailableView {
                Label("تعذر التحميل", systemImage: "wifi.exclamationmark")
            } description: { Text(e) } actions: {
                if let r = retry { Button("إعادة المحاولة") { Task { await r() } }.buttonStyle(.glass) }
            }
        } else { ProgressView().frame(maxWidth: .infinity, minHeight: 160) }
    }
}

/// Match row card with long-press quick preview + actions (contextMenu with preview).
struct MatchRow: View {
    let f: Fixture
    @Environment(AppStore.self) private var store
    @State private var toast: String?
    var body: some View {
        NavigationLink(value: Route.match(f.id)) {
            HStack(spacing: 10) {
                teamCol(f.home)
                VStack(spacing: 4) {
                    if f.isUpcoming { Text(Fmt.time(f.kickoff)).font(.headline).monospacedDigit() }
                    else { Text(f.scoreText).font(.title3.bold()).monospacedDigit().environment(\.layoutDirection, .leftToRight) }
                    StatusBadge(f: f)
                }.frame(width: 92)
                teamCol(f.away)
            }
            .padding(.vertical, 12).padding(.horizontal, 10)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { store.toggleSaved(f.id) } label: { Label(store.savedMatches.contains(f.id) ? "إزالة من المحفوظة" : "حفظ المباراة", systemImage: "bookmark") }
            Button { store.toggleFav(f.home) } label: { Label("مفضلة: \(f.home.name)", systemImage: store.isFav(team: f.home.id) ? "star.fill" : "star") }
            Button { store.toggleFav(f.away) } label: { Label("مفضلة: \(f.away.name)", systemImage: store.isFav(team: f.away.id) ? "star.fill" : "star") }
            if f.isUpcoming { Button { Task { try? await CalendarService.add(f) } } label: { Label("أضف لتقويم الآيفون", systemImage: "calendar.badge.plus") } }
            if f.isLive || f.isUpcoming { Button { _ = try? LiveActivities.start(for: f) } label: { Label("تابع على شاشة القفل", systemImage: "platter.filled.bottom.iphone") } }
        } preview: {
            MatchPreview(f: f).environment(store)
        }
    }
    func teamCol(_ t: TeamRef) -> some View {
        VStack(spacing: 6) {
            RemoteImage(url: t.logo, size: 38)
            Text(t.name).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity)
    }
}

struct MatchPreview: View {
    let f: Fixture
    var body: some View {
        VStack(spacing: 12) {
            HStack { RemoteImage(url: f.league.logo, fallback: "trophy", size: 20); Text(f.league.name).font(.caption); Spacer(); StatusBadge(f: f) }
            HStack {
                VStack { RemoteImage(url: f.home.logo, size: 56); Text(f.home.name).font(.subheadline.bold()) }.frame(maxWidth: .infinity)
                Text(f.isUpcoming ? Fmt.time(f.kickoff) : f.scoreText).font(.largeTitle.bold()).monospacedDigit()
                VStack { RemoteImage(url: f.away.logo, size: 56); Text(f.away.name).font(.subheadline.bold()) }.frame(maxWidth: .infinity)
            }
            if let v = f.venue { Label(v, systemImage: "sportscourt").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(20).frame(width: 340)
    }
}

enum Route: Hashable { case match(Int), league(Int), team(Int), player(Int), notifications, settings, calendar, leagues }

extension View {
    func barqDestinations() -> some View {
        navigationDestination(for: Route.self) { r in
            switch r {
            case .match(let id): MatchCenterView(fixtureId: id)
            case .league(let id): LeagueCenterView(leagueId: id)
            case .team(let id): ClubView(teamId: id)
            case .player(let id): PlayerView(playerId: id)
            case .notifications: NotificationsView()
            case .settings: SettingsView()
            case .calendar: CalendarView()
            case .leagues: LeaguesView()
            case .news: NewsView()
            }
        }
    }
    func screenBackground() -> some View {
        background(
            LinearGradient(colors: [Color.blue.opacity(0.22), Color.clear, Color.purple.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        )
    }
}

