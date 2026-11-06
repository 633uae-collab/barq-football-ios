import SwiftUI
import UserNotifications

/// One transfer row for the News screen. Built only from `/api/team` payloads (API-SPORTS), never from an article feed.
struct NewsItem: Identifiable, Hashable {
    var sourceTeam: Int
    var sourceName: String
    var sourceLogo: String?
    var playerId: Int?
    var player: String
    var date: String
    var type: String
    var fromName: String
    var toName: String
    var fromLogo: String?
    var toLogo: String?
    var moveKey: String
    var id: String
}

struct NewsClub: Hashable {
    var id: Int
    var name: String
    var logo: String?
    var transfers: [Transfer]
}

enum NewsFeed {
    static let maxTeams = 8
    static let limit = 40

    static func items(_ clubs: [NewsClub]) -> [NewsItem] {
        clubs.flatMap { c in
            c.transfers.map { t in
                let who = t.player.id.map(String.init) ?? (t.player.name ?? "")
                let move = "\(who)|\(t.date ?? "")|\(t.type ?? "")|\(t.out.id ?? 0)|\(t.in.id ?? 0)"
                let kind = t.type.flatMap { $0.isEmpty || $0 == "-" ? nil : $0 } ?? ""
                return NewsItem(sourceTeam: c.id, sourceName: c.name, sourceLogo: c.logo, playerId: t.player.id, player: t.player.name ?? "",
                                date: t.date ?? "", type: kind, fromName: t.out.name ?? "", toName: t.in.name ?? "",
                                fromLogo: t.out.logo, toLogo: t.in.logo, moveKey: move, id: "\(c.id)|\(move)")
            }
        }
    }

    /// All clubs: one row per move (a deal listed by two favourites is not repeated). One club: that club's own list.
    static func visible(_ items: [NewsItem], team: Int?, limit: Int = NewsFeed.limit) -> [NewsItem] {
        let base: [NewsItem]
        if let team {
            base = items.filter { $0.sourceTeam == team }
        } else {
            var seen = Set<String>()
            base = items.filter { seen.insert($0.moveKey).inserted }
        }
        let sorted = base.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            if a.player != b.player { return a.player < b.player }
            return a.id < b.id
        }
        return Array(sorted.prefix(limit))
    }

    static func teams(_ items: [NewsItem]) -> [NewsClub] {
        var seen = Set<Int>(), out: [NewsClub] = []
        for i in items where seen.insert(i.sourceTeam).inserted {
            out.append(NewsClub(id: i.sourceTeam, name: i.sourceName, logo: i.sourceLogo, transfers: []))
        }
        return out
    }
}

struct NewsView: View {
    @Environment(AppStore.self) private var store
    @State private var items: [NewsItem]?
    @State private var error: String?
    @State private var team: Int?
    var body: some View {
        let clubs = NewsFeed.teams(items ?? [])
        let selected = clubs.contains(where: { $0.id == team }) ? team : nil
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("لا نعرض أخباراً أو صوراً غير موثقة. الانتقالات أدناه من بيانات API-SPORTS.", systemImage: "checkmark.seal")
                    .font(.footnote).padding().frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                if store.favTeams.isEmpty {
                    EmptyState(symbol: "star", title: "أضف أندية مفضلة لعرض انتقالاتها")
                } else {
                    LoadState(value: items, error: error, retry: load) { items in
                        VStack(alignment: .leading, spacing: 12) {
                            if clubs.count > 1 { filters(clubs, selected: selected) }
                            SectionHeader(title: "الانتقالات", symbol: "arrow.left.arrow.right")
                            let list = NewsFeed.visible(items, team: selected)
                            if list.isEmpty { EmptyState(symbol: "arrow.left.arrow.right", title: "لا توجد انتقالات لهذه الأندية") }
                            ForEach(list) { item in row(item, showClub: selected == nil && clubs.count > 1) }
                        }
                    }
                }
            }.padding()
        }
        .screenBackground()
        .navigationTitle("الأخبار")
        .task(id: store.favTeams.map(\.id)) { team = nil; items = nil; await load() }
        .refreshable { await load() }
    }

    func filters(_ clubs: [NewsClub], selected: Int?) -> some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip("كل الفرق", on: selected == nil, id: "news-filter-all") { team = nil }
                    ForEach(clubs, id: \.id) { c in
                        chip(verbatim: c.name, on: selected == c.id, id: "news-filter-\(c.id)") { team = c.id }
                    }
                }.padding(.vertical, 2)
            }
        }.scrollIndicators(.hidden)
    }

    func chip(_ title: LocalizedStringKey, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        chipLabel(Text(title), on: on, id: id, action: action)
    }
    func chip(verbatim title: String, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        chipLabel(Text(verbatim: title), on: on, id: id, action: action)
    }
    func chipLabel(_ title: Text, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title.font(.subheadline.weight(.semibold)).fixedSize()
                .padding(.horizontal, 14).frame(minHeight: 40)
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? Color.black : Color.primary)
        .glassEffect(on ? .regular.tint(Color("BrandGreen")).interactive() : .regular.interactive(), in: .capsule)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder func row(_ item: NewsItem, showClub: Bool) -> some View {
        let card = HStack(spacing: 8) {
            RemoteImage(url: item.fromLogo, size: 28)
            Image(systemName: "arrow.forward").font(.caption).foregroundStyle(.secondary)
            RemoteImage(url: item.toLogo, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.player).font(.subheadline.bold()).lineLimit(1)
                HStack(spacing: 6) {
                    if showClub { Text(verbatim: item.sourceName).lineLimit(1) }
                    if !item.type.isEmpty { Text(verbatim: item.type) }
                    Text(verbatim: item.date).monospacedDigit()
                }.font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("news-row-\(item.id)")
        if let id = item.playerId {
            NavigationLink(value: Route.player(id)) { card }.buttonStyle(.plain)
        } else {
            card
        }
    }

    func load() async {
        let teams = Array(store.favTeams.prefix(NewsFeed.maxTeams))
        guard !teams.isEmpty else { items = []; error = nil; return }
        struct Page { var index: Int; var response: TeamResponse? }
        let loaded: [Page] = await withTaskGroup(of: Page.self) { group in
            for (i, t) in teams.enumerated() {
                group.addTask {
                    let r: TeamResponse? = try? await API.shared.get("/api/team/\(t.id)", maxAge: 600)
                    return Page(index: i, response: r)
                }
            }
            var bag: [Page] = []
            for await x in group { bag.append(x) }
            return bag
        }
        var clubs: [NewsClub] = []
        var any = false
        for page in loaded.sorted(by: { $0.index < $1.index }) {
            let i = page.index, r = page.response
            if r != nil { any = true }
            let t = teams[i]
            clubs.append(NewsClub(id: t.id, name: r?.team?.name ?? t.name, logo: r?.team?.logo ?? t.logo, transfers: r?.transfers ?? []))
        }
        if !any {
            if items == nil { error = L.s("الخادم غير متاح مؤقتاً، جرّب بعد شوي") }
            return
        }
        items = NewsFeed.items(clubs)
        error = nil
    }
}

struct FavoritesView: View {
    @Environment(AppStore.self) private var store
    @State private var upcoming: [Fixture] = []
    @State private var saved: [Fixture] = []
    @State private var editing = false
    var body: some View {
        List {
            if !saved.isEmpty {
                Section {
                    ForEach(saved) { MatchRow(f: $0).listRowBackground(Color.clear).listRowSeparator(.hidden) }
                } header: { Label("مبارياتي المحفوظة", systemImage: "bookmark.fill") }
            }
            if store.favTeams.isEmpty {
                EmptyState(symbol: "star", title: "ما عندك فرق مفضلة", message: "اضغط النجمة في صفحة أي فريق أو اضغط مطولاً على مباراة").listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(store.favTeams) { t in
                        HStack(spacing: 12) {
                            NavigationLink(value: Route.team(t.id)) {
                                HStack(spacing: 12) {
                                    RemoteImage(url: t.logo, size: 34).padding(8).glassEffect(.regular, in: .circle)
                                    Text(t.name).font(.headline)
                                    Spacer()
                                }
                            }
                            Button { store.toggleMuted(t.id) } label: {
                                Image(systemName: store.mutedTeams.contains(t.id) ? "bell.slash" : "bell.fill")
                                    .foregroundStyle(.secondary).frame(width: 44, height: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text(store.mutedTeams.contains(t.id) ? "الإشعارات مكتومة" : "الإشعارات مفعلة"))
                            .accessibilityIdentifier("fav-mute-\(t.id)")
                        }.listRowBackground(Color.clear)
                    }
                    .onMove { store.favTeams.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { store.favTeams.remove(atOffsets: $0) }
                } header: { Label("فرقي", systemImage: "star.fill") }
                if !upcoming.isEmpty {
                    Section {
                        ForEach(upcoming) { MatchRow(f: $0).listRowBackground(Color.clear).listRowSeparator(.hidden) }
                    } header: { Label("مبارياتهم القادمة", systemImage: "clock") }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .environment(\.editMode, .constant(editing ? .active : .inactive))
        .navigationTitle("المفضلة")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button(editing ? "تم" : "ترتيب", systemImage: editing ? "checkmark" : "arrow.up.arrow.down") { editing.toggle() } }
            ToolbarItem(placement: .topBarLeading) { NavigationLink(value: Route.leagues) { Image(systemName: "trophy") } }
        }
        .barqDestinations()
        .task(id: store.favTeams.map(\.id)) {
            var out: [Fixture] = []
            for t in store.favTeams.prefix(6) {
                if let r: TeamResponse = try? await API.shared.get("/api/team/\(t.id)", maxAge: 1800) { out += (r.next ?? []).prefix(2) }
            }
            upcoming = Array(Set(out)).sorted { $0.ts < $1.ts }
        }
        .task(id: store.savedMatches) {
            var out: [Fixture] = []
            for id in store.savedMatches.suffix(15) {
                if let d: MatchDetail = try? await API.shared.get("/api/match/\(id)", maxAge: 60) { out.append(d.match) }
            }
            saved = out.sorted { $0.ts > $1.ts }
        }
    }
}

struct SearchView: View {
    var initialQuery = ""
    @State private var q = ""
    @State private var r: SearchResponse?
    @State private var loading = false
    @State private var error: String?
    @State private var retry = 0
    var body: some View {
        List {
            if let error {
                Section {
                    Text(error).font(.footnote)
                    Button("إعادة المحاولة") { retry += 1 }.buttonStyle(.glass).accessibilityIdentifier("search-retry")
                }.listRowBackground(Color.clear)
            }
            if let r {
                if let t = r.translated { Label("بحثنا عن: \(t)", systemImage: "character.book.closed").font(.caption).foregroundStyle(.secondary) }
                if !r.leagues.isEmpty { Section { ForEach(r.leagues) { l in link(.league(l.id), l.logo, "trophy", l.name, l.en) } } header: { Label("البطولات", systemImage: "trophy") } }
                if !r.teams.isEmpty { Section { ForEach(r.teams) { t in link(.team(t.id), t.logo, "shield", t.name, t.country) } } header: { Label("الفرق", systemImage: "shield") } }
                if !r.players.isEmpty { Section { ForEach(r.players) { p in link(.player(p.id), p.photo, "person.crop.circle", p.name, p.position, circle: true) } } header: { Label("اللاعبون", systemImage: "person") } }
                if !r.matches.isEmpty { Section { ForEach(r.matches) { MatchRow(f: $0).listRowBackground(Color.clear) } } header: { Label("المباريات", systemImage: "soccerball") } }
                if r.leagues.isEmpty && r.teams.isEmpty && r.players.isEmpty && r.matches.isEmpty && !loading {
                    EmptyState(symbol: "magnifyingglass", title: "ما لقينا نتائج").listRowBackground(Color.clear)
                }
            } else {
                Section { ForEach(["ريال مدريد", "الهلال", "العين", "صلاح", "دوري أبطال أوروبا"], id: \.self) { s in Button { q = s } label: { Label(s, systemImage: "sparkle.magnifyingglass") } } } header: { Text("اقتراحات") }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("بحث")
        .searchable(text: $q, prompt: "فريق، لاعب، بطولة")
        .onAppear { if q.isEmpty && !initialQuery.isEmpty { q = initialQuery } }
        .overlay { if loading { ProgressView() } }
        .barqDestinations()
        .task(id: "\(q)|\(retry)") {
            let term = q.trimmingCharacters(in: .whitespaces)
            r = nil; error = nil; loading = false
            guard term.count >= 2 else { return }
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard !Task.isCancelled else { return }
            loading = true
            let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))
            let enc = term.addingPercentEncoding(withAllowedCharacters: allowed) ?? term
            do {
                let response: SearchResponse = try await API.shared.get("/api/search?q=\(enc)", maxAge: 300)
                guard !Task.isCancelled else { return }
                r = response; loading = false
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription; loading = false
            }
        }
    }

    func link(_ route: Route, _ img: String?, _ fb: String, _ title: String, _ sub: String?, circle: Bool = false) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                RemoteImage(url: img, fallback: fb, size: 36, circle: circle)
                VStack(alignment: .leading) { Text(title).font(.subheadline.bold()); if let s = sub { Text(s).font(.caption).foregroundStyle(.secondary) } }
            }
        }.listRowBackground(Color.clear)
    }
}

enum NoteKind: String, CaseIterable { case all, ai, goals, results
    var title: LocalizedStringKey { switch self { case .all: "الكل"; case .ai: "تحليلات"; case .goals: "أحداث"; case .results: "نتائج" } }
    var symbol: String { switch self { case .all: "tray.full"; case .ai: "brain.head.profile"; case .goals: "soccerball.inverse"; case .results: "flag.checkered" } }
    func match(_ i: Insight) -> Bool {
        switch self {
        case .all: true
        case .ai: ["pressure", "shift", "possession"].contains(i.type)
        case .goals: ["goal", "red", "kickoff", "second"].contains(i.type)
        case .results: ["ht", "ft"].contains(i.type)
        }
    }
}

/// Pure helpers for the notifications list (dedupe + day/match grouping), unit tested.
enum NoteGrouping {
    struct Group: Identifiable { var id: String; var day: Date; var fixture: Int; var items: [Insight] }
    static func dedupe(_ list: [Insight]) -> [Insight] {
        var seen = Set<Int>(), seenKey = Set<String>()
        return list.filter { i in
            let k = "\(i.fixture)|\(i.type)|\(i.minute)|\(i.title)"
            return seen.insert(i.id).inserted && seenKey.insert(k).inserted
        }
    }
    /// Newest day first; inside a day, matches ordered by their latest note; notes newest first.
    static func groups(_ list: [Insight], calendar: Calendar = .current) -> [Group] {
        let items = dedupe(list).sorted { $0.at > $1.at }
        var order: [String] = [], map: [String: Group] = [:]
        for i in items {
            let day = calendar.startOfDay(for: i.date)
            let key = "\(Int(day.timeIntervalSince1970))-\(i.fixture)"
            if map[key] == nil { order.append(key); map[key] = Group(id: key, day: day, fixture: i.fixture, items: []) }
            map[key]!.items.append(i)
        }
        return order.compactMap { map[$0] }
    }
    static func tint(_ type: String) -> Color {
        switch type {
        case "goal": Color("BrandGreen")
        case "red": .red
        case "ht", "ft", "second", "kickoff": .orange
        case "pressure", "shift", "possession": .cyan
        default: .secondary
        }
    }
    static func clean(_ s: String) -> String { s.replacingOccurrences(of: " — ", with: " · ") }
}

struct NotificationsView: View {
    @Environment(AppStore.self) private var store
    @State private var kind: NoteKind = .all
    var body: some View {
        @Bindable var s = store
        let groups = NoteGrouping.groups(store.notifications.filter(kind.match))
        List {
            Section {
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(NoteKind.allCases, id: \.self) { k in
                                Button { withAnimation(.smooth) { kind = k } } label: {
                                    Label(k.title, systemImage: k.symbol).font(.subheadline.weight(.semibold)).fixedSize()
                                        .padding(.horizontal, 14).frame(minHeight: 40)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(kind == k ? Color.black : Color.primary)
                                .glassEffect(kind == k ? .regular.tint(Color("BrandGreen")).interactive() : .regular.interactive(), in: .capsule)
                                .accessibilityIdentifier("notif-filter-\(k.rawValue)")
                                .accessibilityAddTraits(kind == k ? .isSelected : [])
                            }
                        }.padding(.vertical, 2)
                    }
                }.scrollIndicators(.hidden)
                Picker(selection: $s.alertDensity) {
                    Text("المهم فقط").tag(0); Text("متوازن").tag(1); Text("الكل").tag(2)
                } label: { Label("كثافة التنبيهات", systemImage: "slider.horizontal.3") }
            }.listRowBackground(Color.clear)
            if groups.isEmpty { EmptyState(symbol: "bell", title: "لا توجد إشعارات").listRowBackground(Color.clear) }
            ForEach(groups) { g in
                Section {
                    ForEach(g.items) { i in
                        NavigationLink(value: Route.match(i.fixture)) { NoteRow(i: i) }
                            .listRowBackground(Color.clear)
                            .accessibilityIdentifier("notif-\(i.id)")
                    }
                } header: { header(g) }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("الإشعارات")
        .onAppear { store.unread = 0 }
    }

    func header(_ g: NoteGrouping.Group) -> some View {
        let m = g.items.first?.match
        return HStack(spacing: 6) {
            if let m {
                RemoteImage(url: m.homeLogo, size: 18)
                Text(verbatim: "\(m.home) \(m.score ?? "×") \(m.away)").lineLimit(1).minimumScaleFactor(0.8)
                RemoteImage(url: m.awayLogo, size: 18)
            } else { Text("مباراة") }
            Spacer()
            Text(Fmt.dateLabel(g.day)).foregroundStyle(.secondary)
        }.font(.caption.bold()).textCase(nil)
    }
}

struct NoteRow: View {
    let i: Insight
    var logo: String? {
        guard let m = i.match, let t = i.team, !t.isEmpty else { return nil }
        return t == m.home ? m.homeLogo : (t == m.away ? m.awayLogo : nil)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                if let logo { RemoteImage(url: logo, size: 30).frame(width: 38, height: 38).glassEffect(.regular, in: .circle) }
                else {
                    Image(systemName: i.symbol).font(.body.weight(.semibold)).foregroundStyle(NoteGrouping.tint(i.type))
                        .frame(width: 38, height: 38).glassEffect(.regular, in: .circle)
                }
                if logo != nil {
                    Image(systemName: i.symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 18, height: 18).background(NoteGrouping.tint(i.type), in: .circle)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: NoteGrouping.clean(i.title)).font(.subheadline.bold()).lineLimit(2)
                    Spacer(minLength: 4)
                    Text(verbatim: "\(i.minute)'").font(.caption.bold()).monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(NoteGrouping.tint(i.type).opacity(0.18), in: .capsule)
                }
                Text(verbatim: NoteGrouping.clean(i.body)).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                Text(Fmt.ago(i.date)).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var notifOK: Bool?
    @AppStorage("apiOverride") private var apiOverride = ""
    @State private var editFavs = false
    static let zones = ["Asia/Dubai", "Asia/Riyadh", "Asia/Qatar", "Asia/Kuwait", "Africa/Cairo", "Europe/London", "UTC"]
    var body: some View {
        @Bindable var s = store
        Form {
            Section {
                Button { editFavs = true } label: { Label("تعديل الأندية والدوريات المفضلة", systemImage: "star.circle") }
                    .accessibilityIdentifier("settings-edit-favorites")
            } header: { Text("المفضلة") }
            Section {
                Picker(selection: $s.theme) {
                    Label("حسب الجهاز", systemImage: "iphone").tag(ThemeMode.system)
                    Label("ليلي", systemImage: "moon.fill").tag(ThemeMode.dark)
                    Label("نهاري", systemImage: "sun.max.fill").tag(ThemeMode.light)
                } label: { Label("المظهر", systemImage: "circle.lefthalf.filled") }
                HStack {
                    Label("لون التطبيق", systemImage: "paintpalette")
                    Spacer()
                    ForEach(AppStore.accents.indices, id: \.self) { ai in
                        let k = AppStore.accents[ai].0, c = AppStore.accents[ai].1
                        Button { s.accentKey = k } label: { Circle().fill(c).frame(width: 22, height: 22).overlay { if s.accentKey == k { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white) } } }.buttonStyle(.plain)
                    }
                }
            } header: { Text("المظهر") }
            Section {
                Picker(selection: $s.lang) { Text("العربية").tag("ar"); Text("English").tag("en") } label: { Label("اللغة", systemImage: "globe") }
                Picker(selection: $s.tz) { ForEach(Self.zones, id: \.self) { Text($0).tag($0) } } label: { Label("المنطقة الزمنية", systemImage: "clock") }
            } header: { Text("اللغة والمنطقة") }
            Section {
                HStack {
                    Label("إذن الإشعارات", systemImage: "bell.badge")
                    Spacer()
                    Text(notifStatusText).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("settings-notif-status")
                }
                if notifStatus != .authorized {
                    Button { Task { notifOK = await Notifier.requestPermission(); await refreshStatus() } } label: { Label("طلب إذن الإشعارات", systemImage: "hand.tap") }
                }
                if notifOK == false { Text("تم الرفض، فعّلها من إعدادات الآيفون").font(.caption).foregroundStyle(.secondary) }
                Picker(selection: $s.alertDensity) { Text("المهم فقط").tag(0); Text("متوازن").tag(1); Text("الكل").tag(2) } label: { Label("كثافة التنبيهات", systemImage: "slider.horizontal.3") }
                    .accessibilityIdentifier("settings-density")
                Text("المهم فقط: الأهداف والطرد والنهاية. متوازن: يضيف الاستراحة وأهم التحليلات. الكل: كل التحليلات.").font(.caption).foregroundStyle(.secondary)
            } header: { Text("الإشعارات") } footer: {
                Label("إشعارات الخادم الفورية تحتاج اختباراً على آيفون حقيقي بعد التوقيع.", systemImage: "iphone.gen3").font(.caption)
            }
            Section {
                HStack {
                    Label("الأنشطة المباشرة", systemImage: "platter.filled.bottom.iphone")
                    Spacer()
                    Text(LiveActivities.enabled ? "مسموحة في النظام" : "متوقفة من إعدادات الآيفون").font(.footnote).foregroundStyle(.secondary)
                }
                Text("تظهر نتيجة مباريات فرقك المفضلة على شاشة القفل والجزيرة التفاعلية.").font(.caption).foregroundStyle(.secondary)
            } header: { Text("الأنشطة المباشرة والجزيرة التفاعلية") } footer: {
                Label("لم تُختبر بعد على آيفون حقيقي، تحتاج اختباراً فعلياً قبل اعتمادها.", systemImage: "exclamationmark.triangle").font(.caption)
            }
            Section {
                Label("لا نجمع أي بيانات شخصية. المفضلة محفوظة بمعرّف جهاز عشوائي.", systemImage: "hand.raised").font(.footnote)
                TextField("عنوان الخادم (اختياري)", text: $apiOverride).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit { Task { await API.shared.resetBase() } }
            } header: { Text("الخصوصية والخادم") }
            Section {
                Text("البيانات من API-SPORTS عبر خادم FOTIQ. مفتاح API لا يُخزن في التطبيق.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("الإعدادات")
        .task { await refreshStatus() }
        .fullScreenCover(isPresented: $editFavs) { OnboardingView(editing: true) { editFavs = false } }
    }

    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    var notifStatusText: LocalizedStringKey {
        switch notifStatus {
        case .authorized, .provisional, .ephemeral: "مفعّل"
        case .denied: "مرفوض"
        default: "غير محدد"
        }
    }
    func refreshStatus() async { notifStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
}
