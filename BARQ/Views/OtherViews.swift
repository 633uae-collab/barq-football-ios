import SwiftUI

struct NewsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                EmptyState(symbol: "newspaper", title: "الأخبار قريباً", message: "ننتظر ربط مصدر أخبار مرخّص. لن نعرض أخباراً أو صوراً غير موثقة.")
                // Planned layout (enabled once a licensed feed is wired): hero cards, compact list, team filter, AI summary, transfers.
                Label("انتقالات فرقك المفضلة متاحة من صفحة كل نادي", systemImage: "arrow.left.arrow.right")
                    .font(.footnote).padding().glassEffect(.regular, in: .rect(cornerRadius: 16))
            }.padding()
        }
        .screenBackground()
        .navigationTitle("الأخبار")
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
                        NavigationLink(value: Route.team(t.id)) {
                            HStack(spacing: 12) {
                                RemoteImage(url: t.logo, size: 34).padding(8).glassEffect(.regular, in: .circle)
                                Text(t.name).font(.headline)
                                Spacer()
                                Image(systemName: store.mutedTeams.contains(t.id) ? "bell.slash" : "bell.fill").foregroundStyle(.secondary)
                            }
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
    var body: some View {
        List {
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
        .task(id: q) {
            let term = q.trimmingCharacters(in: .whitespaces)
            guard term.count >= 2 else { r = nil; return }
            try? await Task.sleep(for: .milliseconds(350)) // debounce, cancelled by next keystroke
            guard !Task.isCancelled else { return }
            loading = true; defer { loading = false }
            let enc = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
            r = try? await API.shared.get("/api/search?q=\(enc)", maxAge: 300)
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
        switch self { case .all: true; case .ai: ["pressure", "shift", "possession"].contains(i.type); case .goals: i.type == "red"; case .results: ["ht", "ft"].contains(i.type) }
    }
}

struct NotificationsView: View {
    @Environment(AppStore.self) private var store
    @State private var kind: NoteKind = .all
    var body: some View {
        @Bindable var s = store
        List {
            Section {
                Picker("النوع", selection: $kind) { ForEach(NoteKind.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) } }.pickerStyle(.segmented)
                Picker(selection: $s.alertDensity) {
                    Text("المهم فقط").tag(0); Text("متوازن").tag(1); Text("الكل").tag(2)
                } label: { Label("كثافة التنبيهات", systemImage: "slider.horizontal.3") }
            }
            let list = store.notifications.filter(kind.match)
            if list.isEmpty { EmptyState(symbol: "bell", title: "لا توجد إشعارات").listRowBackground(Color.clear) }
            ForEach(list) { i in
                NavigationLink(value: Route.match(i.fixture)) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: i.symbol).font(.title3).foregroundStyle(["pressure", "shift", "possession"].contains(i.type) ? .cyan : .secondary)
                            .frame(width: 36, height: 36).glassEffect(.regular, in: .circle)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(i.title).font(.subheadline.bold())
                            Text(i.body).font(.caption).foregroundStyle(.secondary)
                            Text(Fmt.ago(i.date)).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }.listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("الإشعارات")
        .onAppear { store.unread = 0 }
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var notifOK: Bool?
    @AppStorage("apiOverride") private var apiOverride = ""
    static let zones = ["Asia/Dubai", "Asia/Riyadh", "Asia/Qatar", "Asia/Kuwait", "Africa/Cairo", "Europe/London", "UTC"]
    var body: some View {
        @Bindable var s = store
        Form {
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
                Button { Task { notifOK = await Notifier.requestPermission() } } label: { Label("تفعيل الإشعارات", systemImage: "bell.badge") }
                if let ok = notifOK { Text(ok ? "تم التفعيل" : "تم الرفض، فعّلها من إعدادات الآيفون").font(.caption) }
                Label(LiveActivities.enabled ? "Live Activities مفعلة" : "Live Activities غير مفعلة", systemImage: "platter.filled.bottom.iphone")
                Picker(selection: $s.alertDensity) { Text("المهم فقط").tag(0); Text("متوازن").tag(1); Text("الكل").tag(2) } label: { Label("كثافة التنبيهات", systemImage: "slider.horizontal.3") }
            } header: { Text("الإشعارات") }
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
    }
}
