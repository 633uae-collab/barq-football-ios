import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @State private var today: [Fixture] = []
    @State private var top: [Fixture] = []
    @State private var latestAI: Insight?
    @State private var error: String?
    @State private var loaded = false
    @State private var editing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let e = error, !loaded {
                    EmptyState(symbol: "wifi.exclamationmark", title: "تعذر التحميل", message: LocalizedStringKey(e))
                }
                ForEach(store.homeSections, id: \.self) { key in section(key).transition(.opacity) }
            }
            .animation(.smooth(duration: 0.3), value: store.homeSections)
            .animation(.smooth(duration: 0.3), value: loaded)
            .padding(.horizontal)
            .padding(.top, 2)
        }
        // Keep the last row clear of the floating Liquid Glass tab bar.
        .contentMargins(.bottom, 24, for: .scrollContent)
        .safeAreaPadding(.bottom, 8)
        .screenBackground()
        .navigationTitle("FOTIQ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: Route.notifications) {
                    Image(systemName: store.unread > 0 ? "bell.badge" : "bell")
                }
                .accessibilityLabel(Text("الإشعارات"))
                .accessibilityIdentifier("home-notifications")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(value: Route.news) { Image(systemName: "newspaper") }
                    .accessibilityLabel(Text("الأخبار")).accessibilityIdentifier("home-news")
                Button { editing = true } label: { Image(systemName: "rectangle.3.group") }
                    .accessibilityLabel(Text("ترتيب الأقسام")).accessibilityIdentifier("home-reorder")
                NavigationLink(value: Route.settings) { Image(systemName: "gearshape") }
                    .accessibilityLabel(Text("الإعدادات")).accessibilityIdentifier("home-settings")
            }
        }
        .sheet(isPresented: $editing) { ReorderSectionsSheet() }
        .barqDestinations()
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder func section(_ key: String) -> some View {
        switch key {
        case "carousel": if !top.isEmpty { TopCarousel(matches: top) }
        case "ticker":
            let live = today.filter(\.isLive)
            if !live.isEmpty { LiveTicker(matches: live) }
        case "ai":
            if let i = latestAI {
                NavigationLink(value: Route.match(i.fixture)) { InsightCard(insight: i) }.buttonStyle(.plain)
            }
        case "favorites":
            let favIds = Set(store.favTeams.map(\.id))
            let favs = today.filter { favIds.contains($0.home.id) || favIds.contains($0.away.id) }
            if !favs.isEmpty {
                SectionHeader(title: "فرقك اليوم", symbol: "star.fill")
                ForEach(favs) { MatchRow(f: $0) }
            }
        case "today":
            if loaded {
                SectionHeader(title: "مباريات اليوم", symbol: "soccerball")
                let list = Array(MatchSort.byImportance(today).prefix(12))
                if list.isEmpty { EmptyState(symbol: "calendar", title: "لا توجد مباريات اليوم") }
                ForEach(list) { MatchRow(f: $0) }
                NavigationLink(value: Route.leagues) {
                    Label("كل الدوريات", systemImage: "trophy").frame(maxWidth: .infinity)
                }.buttonStyle(.glass)
            }
        default: EmptyView()
        }
    }

    func load() async {
        do {
            async let a: FixturesResponse = API.shared.get("/api/fixtures?date=\(Fmt.day(0))", maxAge: 15)
            async let b: FixturesResponse? = try? API.shared.get("/api/fixtures?date=\(Fmt.day(1))", maxAge: 600)
            async let c: FeedResponse? = try? API.shared.get("/api/feed", maxAge: 30)
            let (t, tm, feed) = try await (a, b, c)
            today = t.fixtures
            top = MatchSort.topN(today: t.fixtures, tomorrow: tm?.fixtures ?? [])
            latestAI = feed?.insights.first
            loaded = true; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

/// Top-5 carousel: swipe between the most important matches, glass page dots, auto-advance every 6s, pauses on touch.
struct TopCarousel: View {
    let matches: [Fixture]
    @State private var index: Int? = 0
    @State private var paused = false
    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { i, f in
                        NavigationLink(value: Route.match(f.id)) { HeroCard(f: f, rank: i + 1, total: matches.count) }
                            .buttonStyle(.plain)
                            .containerRelativeFrame(.horizontal)
                            .id(i)
                    }
                }.scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $index)
            .scrollIndicators(.hidden)
            .simultaneousGesture(DragGesture().onChanged { _ in paused = true })
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 8) {
                    ForEach(matches.indices, id: \.self) { i in
                        Button { withAnimation { index = i } } label: {
                            Circle().fill(i == (index ?? 0) ? Color.accentColor : Color.secondary.opacity(0.4))
                                .frame(width: i == (index ?? 0) ? 10 : 7, height: i == (index ?? 0) ? 10 : 7)
                        }
                        .accessibilityLabel(Text("مباراة \(i + 1)"))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .glassEffect(.regular, in: .capsule)
            }
        }
        .task(id: paused) {
            guard !paused else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                if paused || matches.isEmpty { break }
                withAnimation(.smooth) { index = ((index ?? 0) + 1) % matches.count }
            }
        }
    }
}

/// Team name that wraps to two lines and scales down slightly instead of truncating.
struct TeamName: View {
    let name: String
    var font: Font = .subheadline.bold()
    var body: some View {
        Text(verbatim: name).font(font)
            .lineLimit(2).minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct HeroCard: View {
    let f: Fixture
    let rank: Int
    let total: Int
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                RemoteImage(url: f.league.logo, fallback: "trophy", size: 20)
                Text(f.league.name).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer()
                Text("\(rank) من \(total)").font(.caption.bold()).monospacedDigit()
                    .padding(.horizontal, 8).padding(.vertical, 3).glassEffect(.regular, in: .capsule)
            }
            HStack {
                VStack(spacing: 6) { RemoteImage(url: f.home.logo, size: 52); TeamName(name: f.home.name) }.frame(maxWidth: .infinity)
                VStack(spacing: 6) {
                    Text(f.isUpcoming ? Fmt.time(f.kickoff) : f.scoreText).font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit()
                        .environment(\.layoutDirection, .leftToRight)
                    StatusBadge(f: f)
                    if !Calendar.current.isDateInToday(f.kickoff) { Text(Fmt.dateLabel(f.kickoff)).font(.caption2).foregroundStyle(.secondary) }
                }
                VStack(spacing: 6) { RemoteImage(url: f.away.logo, size: 52); TeamName(name: f.away.name) }.frame(maxWidth: .infinity)
            }
            if let v = f.venue { Label(v, systemImage: "sportscourt").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background {
            // Stadium-style backdrop drawn natively (no stock photo).
            ZStack {
                LinearGradient(colors: [.green.opacity(0.35), .blue.opacity(0.35), .black.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "sportscourt").resizable().scaledToFit().foregroundStyle(.white.opacity(0.06)).padding(10)
            }.clipShape(.rect(cornerRadius: 28))
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
        .padding(.horizontal, 2)
    }
}

struct LiveTicker: View {
    let matches: [Fixture]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "مباشر الآن", symbol: "dot.radiowaves.left.and.right")
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        ForEach(matches) { f in
                            NavigationLink(value: Route.match(f.id)) {
                                HStack(spacing: 8) {
                                    RemoteImage(url: f.home.logo, size: 26)
                                    Text(f.scoreText).font(.headline).monospacedDigit().environment(\.layoutDirection, .leftToRight)
                                    RemoteImage(url: f.away.logo, size: 26)
                                    LivePill(minute: f.status.elapsed, extra: f.status.extra, status: f.status.short)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .frame(minHeight: 48)
                                .contentShape(.capsule)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(Text(verbatim: "\(f.home.name) \(f.scoreText) \(f.away.name)"))
                                .glassEffect(.regular.interactive(), in: .capsule)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }
}

struct InsightCard: View {
    let insight: Insight
    var body: some View {
        GlassCard(interactive: true) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: insight.symbol).font(.title3).foregroundStyle(.cyan)
                    Text(insight.title).font(.subheadline.bold()).lineLimit(2)
                    Spacer()
                    Text("\(insight.minute)'").font(.caption.bold()).monospacedDigit()
                }
                Text(insight.body).font(.callout).foregroundStyle(.secondary)
                if let n = insight.nums, !n.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(n.keys.sorted(), id: \.self) { k in
                            VStack(spacing: 2) { Text(n[k]!.text).font(.caption.bold()).monospacedDigit(); Text(L.metric(k)).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8) }
                        }
                    }
                }
                Text(Fmt.ago(insight.date)).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

struct ReorderSectionsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    static let names: [String: (LocalizedStringKey, String)] = [
        "carousel": ("أهم المباريات", "sparkles.rectangle.stack"), "ticker": ("مباشر الآن", "dot.radiowaves.left.and.right"),
        "ai": ("آخر تحليل AI", "brain.head.profile"), "favorites": ("فرقك اليوم", "star"), "today": ("مباريات اليوم", "soccerball"),
    ]
    var body: some View {
        @Bindable var s = store
        NavigationStack {
            List {
                Section {
                    ForEach(s.homeSections, id: \.self) { k in
                        Label(Self.names[k]?.0 ?? "", systemImage: Self.names[k]?.1 ?? "square")
                            .accessibilityIdentifier("reorder-row-\(k)")
                    }
                    .onMove { s.homeSections.move(fromOffsets: $0, toOffset: $1) }
                } header: { Text("اسحب لتغيير الترتيب") }
                Section {
                    // Live preview: miniature of the Home page in the order being edited.
                    VStack(spacing: 6) {
                        ForEach(Array(s.homeSections.enumerated()), id: \.element) { i, k in
                            HStack(spacing: 10) {
                                Text(verbatim: "\(i + 1)").font(.caption.bold()).monospacedDigit()
                                    .frame(width: 22, height: 22).glassEffect(.regular, in: .circle)
                                Image(systemName: Self.names[k]?.1 ?? "square").foregroundStyle(Color.accentColor)
                                Text(Self.names[k]?.0 ?? "").font(.footnote)
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
                        }
                    }
                    .animation(.smooth, value: s.homeSections)
                    .accessibilityIdentifier("reorder-preview")
                } header: { Text("معاينة الرئيسية") }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("ترتيب الأقسام")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("تم", systemImage: "checkmark") { dismiss() }.buttonStyle(.glassProminent) }
                ToolbarItem(placement: .cancellationAction) { Button("استعادة الافتراضي", systemImage: "arrow.counterclockwise") { withAnimation { s.homeSections = AppStore.defaultSections } }
                        .accessibilityIdentifier("reorder-reset") }
            }
        }
    }
}
