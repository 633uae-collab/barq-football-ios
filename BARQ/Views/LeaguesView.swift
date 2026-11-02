import SwiftUI

struct LeaguesView: View {
    @Environment(AppStore.self) private var store
    @State private var cat: CatalogResponse?
    @State private var error: String?
    @State private var query = ""
    @State private var editFavs = false

    static let continentOrder = ["world", "asia", "europe", "americas", "africa", "other"]

    var body: some View {
        List {
            if let c = cat {
                let filtered = c.leagues.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) || $0.name.localizedCaseInsensitiveContains(query) || ($0.countryAr ?? "").contains(query) }
                let favs = store.favLeagues.compactMap { id in c.leagues.first { $0.id == id } }
                if query.isEmpty && !favs.isEmpty {
                    Section {
                        ForEach(favs) { row($0, featured: true) }
                            .onMove { store.favLeagues.move(fromOffsets: $0, toOffset: $1) }
                    } header: { Label("بطولاتي", systemImage: "star.fill") }
                }
                ForEach(Self.continentOrder, id: \.self) { k in
                    let ls = filtered.filter { ($0.continent ?? "other") == k }
                        .sorted { (c.order?.firstIndex(of: $0.id) ?? 9999, $0.id) < (c.order?.firstIndex(of: $1.id) ?? 9999, $1.id) }
                    if !ls.isEmpty {
                        Section { ForEach(ls) { row($0, featured: false) } } header: { Label(c.continents?[k] ?? k, systemImage: symbol(k)) }
                    }
                }
            } else if let e = error {
                EmptyState(symbol: "wifi.exclamationmark", title: "تعذر التحميل", message: LocalizedStringKey(e))
            } else { ProgressView() }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .environment(\.editMode, .constant(editFavs ? .active : .inactive))
        .searchable(text: $query, prompt: "ابحث عن دوري")
        .navigationTitle("الدوريات")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(editFavs ? "تم" : "ترتيب", systemImage: editFavs ? "checkmark" : "arrow.up.arrow.down") { editFavs.toggle() } } }
        .task {
            do { cat = try await API.shared.get("/api/catalog", maxAge: 3600) } catch { self.error = error.localizedDescription }
        }
    }

    func symbol(_ k: String) -> String {
        switch k { case "world": "globe"; case "asia": "globe.asia.australia"; case "europe": "globe.europe.africa"; case "americas": "globe.americas"; case "africa": "globe.europe.africa.fill"; default: "map" }
    }

    func row(_ l: LeagueMeta, featured: Bool) -> some View {
        NavigationLink(value: Route.league(l.id)) {
            HStack(spacing: 12) {
                RemoteImage(url: l.logo, fallback: "trophy", size: featured ? 40 : 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.displayName).font(featured ? .headline : .subheadline)
                    Text(l.countryAr ?? l.country ?? "").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.toggleLeague(l.id) } label: { Image(systemName: store.favLeagues.contains(l.id) ? "star.fill" : "star").foregroundStyle(.yellow) }.buttonStyle(.borderless)
            }
        }
        .listRowBackground(Color.clear)
    }
}

enum LCTab: String, CaseIterable { case table, scorers, assists, fixtures
    var title: LocalizedStringKey { switch self { case .table: "الترتيب"; case .scorers: "الهدافون"; case .assists: "صناع الأهداف"; case .fixtures: "المباريات" } }
    var symbol: String { switch self { case .table: "list.number"; case .scorers: "soccerball.inverse"; case .assists: "figure.soccer"; case .fixtures: "calendar" } }
}

struct LeagueCenterView: View {
    let leagueId: Int
    @Environment(AppStore.self) private var store
    @State private var tab: LCTab = .table
    @State private var standings: StandingsResponse?
    @State private var scorers: TopPlayersResponse?
    @State private var assists: TopPlayersResponse?
    @State private var fixtures: LeagueFixtures?
    @State private var error: String?
    @State private var season: Int?

    var meta: LeagueMeta? { standings?.league ?? fixtures?.league }
    var seasonQuery: String { season.map { "?season=\($0)" } ?? "" }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    RemoteImage(url: meta?.logo, fallback: "trophy", size: 64)
                    VStack(alignment: .leading) {
                        Text(meta?.displayName ?? "").font(.title2.bold())
                        Text(meta?.countryAr ?? meta?.country ?? "").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { store.toggleLeague(leagueId) } label: { Image(systemName: store.favLeagues.contains(leagueId) ? "star.fill" : "star") }.buttonStyle(.glass)
                }.padding().glassEffect(.regular, in: .rect(cornerRadius: 26))

                Picker("القسم", selection: $tab) { ForEach(LCTab.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) } }.pickerStyle(.segmented)
                if let e = error { Text(e).font(.caption).foregroundStyle(.red) }
                switch tab {
                case .table: table
                case .scorers: players(scorers, goals: true)
                case .assists: players(assists, goals: false)
                case .fixtures:
                    if let f = fixtures {
                        SectionHeader(title: "القادمة", symbol: "clock"); ForEach(f.next) { MatchRow(f: $0) }
                        SectionHeader(title: "النتائج", symbol: "flag.checkered"); ForEach(f.last) { MatchRow(f: $0) }
                    } else { ProgressView() }
                }
            }.padding(.horizontal).padding(.bottom, 30)
        }
        .screenBackground()
        .navigationTitle(meta?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Season picker. Backend needs backend-addons/season.patch to honour ?season=.
                Menu {
                    let cur = meta?.season ?? Calendar.current.component(.year, from: Date())
                    ForEach((cur - 4)...cur, id: \.self) { y in Button("\(String(y))/\(String(y + 1))") { season = y } }
                } label: { Label(String(season ?? meta?.season ?? 0), systemImage: "calendar.badge.clock") }
            }
        }
        .task(id: season) {
            await load()
            while standings == nil, error != nil, !Task.isCancelled { try? await Task.sleep(for: .seconds(5)); await load() }
        }
    }

    var table: some View {
        Group {
            if let s = standings {
                if s.groups.isEmpty { EmptyState(symbol: "list.number", title: "لا يوجد جدول ترتيب لهذه البطولة") }
                ForEach(s.groups.indices, id: \.self) { gi in
                    VStack(spacing: 0) {
                        HStack { Text("#").frame(width: 24); Text("الفريق"); Spacer(); Text("لعب").frame(width: 32); Text("+/-").frame(width: 36); Text("نقاط").frame(width: 40) }
                            .font(.caption.bold()).foregroundStyle(.secondary).padding(.bottom, 6)
                        ForEach(s.groups[gi]) { r in
                            NavigationLink(value: Route.team(r.team.id)) {
                                HStack {
                                    Text("\(r.rank)").frame(width: 24).monospacedDigit()
                                    RemoteImage(url: r.team.logo, size: 22)
                                    Text(r.team.name).lineLimit(1)
                                    Spacer()
                                    Text("\(r.all?.played ?? 0)").frame(width: 32)
                                    Text("\(r.goalsDiff ?? 0)").frame(width: 36)
                                    Text("\(r.points)").bold().frame(width: 40)
                                }.font(.subheadline.monospacedDigit()).padding(.vertical, 6)
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }.padding().glassEffect(.regular, in: .rect(cornerRadius: 22))
                }
            } else { ProgressView() }
        }
    }

    func players(_ r: TopPlayersResponse?, goals: Bool) -> some View {
        Group {
            if let r {
                if r.players.isEmpty { EmptyState(symbol: "person.3", title: "لا توجد بيانات") }
                ForEach(Array(r.players.enumerated()), id: \.element.id) { i, p in
                    NavigationLink(value: Route.player(p.id)) {
                        HStack(spacing: 10) {
                            Text("\(i + 1)").monospacedDigit().frame(width: 22)
                            RemoteImage(url: p.photo, fallback: "person.crop.circle", size: 40, circle: true)
                            VStack(alignment: .leading) { Text(p.name).font(.subheadline.bold()); Text(p.team?.name ?? "").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Text("\(goals ? (p.goals ?? 0) : (p.assists ?? 0))").font(.title3.bold()).monospacedDigit()
                        }.padding(10).glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                    }.buttonStyle(.plain)
                }
            } else { ProgressView() }
        }
    }

    func load() async {
        do {
            async let a: StandingsResponse = API.shared.get("/api/standings/\(leagueId)\(seasonQuery)", maxAge: 300)
            async let b: TopPlayersResponse? = try? API.shared.get("/api/topscorers/\(leagueId)\(seasonQuery)", maxAge: 3600)
            async let c: TopPlayersResponse? = try? API.shared.get("/api/topassists/\(leagueId)\(seasonQuery)", maxAge: 3600)
            async let d: LeagueFixtures? = try? API.shared.get("/api/league/\(leagueId)\(seasonQuery)", maxAge: 300)
            let (s, sc, asx, fx) = try await (a, b, c, d)
            standings = s; scorers = sc; assists = asx; fixtures = fx; error = nil
        } catch { self.error = error.localizedDescription }
    }
}
