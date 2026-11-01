import SwiftUI

enum MatchFilter: String, CaseIterable { case all, live, upcoming, finished
    var title: LocalizedStringKey { switch self { case .all: "الكل"; case .live: "مباشر"; case .upcoming: "القادمة"; case .finished: "انتهت" } }
    var symbol: String { switch self { case .all: "list.bullet"; case .live: "dot.radiowaves.left.and.right"; case .upcoming: "clock"; case .finished: "flag.checkered" } }
}

struct MatchesView: View {
    @Environment(AppStore.self) private var store
    @State private var day = 0
    @State private var filter: MatchFilter = .all
    @State private var data: FixturesResponse?
    @State private var error: String?
    @State private var showAllLeagues = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                DayStrip(offset: $day, highlight: Set<Int>())
                Picker("الحالة", selection: $filter) {
                    ForEach(MatchFilter.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }.pickerStyle(.segmented)
                LoadState(value: data, error: error, retry: load) { d in
                    let groups = grouped(d)
                    if groups.isEmpty { EmptyState(symbol: "soccerball", title: "لا توجد مباريات") }
                    LazyVStack(spacing: 10) {
                        ForEach(groups.indices, id: \.self) { gi in
                            let lg = groups[gi].0, list = groups[gi].1
                            NavigationLink(value: Route.league(lg.id)) {
                                HStack { RemoteImage(url: lg.logo, fallback: "trophy", size: 22); Text(lg.name).font(.subheadline.bold()); Spacer(); Image(systemName: "chevron.left").font(.caption) }
                            }.buttonStyle(.plain).padding(.top, 6)
                            ForEach(list) { MatchRow(f: $0) }
                        }
                    }
                }
            }.padding(.horizontal).padding(.bottom, 30)
        }
        .screenBackground()
        .navigationTitle("المباريات")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { NavigationLink(value: Route.calendar) { Image(systemName: "calendar") } }
        }
        .barqDestinations()
        .task(id: day) { data = nil; await load() }
        .refreshable { await load() }
        .task(id: day) {
            // live refresh every 15s while viewing today
            while day == 0 && !Task.isCancelled { try? await Task.sleep(for: .seconds(15)); await load() }
        }
    }

    func load() async {
        do { data = try await API.shared.get("/api/fixtures?date=\(Fmt.day(day))", maxAge: 10); error = nil }
        catch { self.error = error.localizedDescription }
    }

    /// Leagues ordered by their best match importance; matches inside by importance.
    func grouped(_ d: FixturesResponse) -> [(LeagueRef, [Fixture])] {
        let list = d.fixtures.filter {
            switch filter { case .all: true; case .live: $0.isLive; case .upcoming: $0.isUpcoming; case .finished: $0.isDone }
        }
        let byLeague = Dictionary(grouping: list, by: { $0.league.id })
        return byLeague.values.map { fs in (fs[0].league, MatchSort.byImportance(fs)) }
            .sorted { a, b in
                let fa = store.favLeagues.firstIndex(of: a.0.id) ?? 999, fb = store.favLeagues.firstIndex(of: b.0.id) ?? 999
                if fa != fb { return fa < fb }
                let ia = a.1.first?.importance ?? 0, ib = b.1.first?.importance ?? 0
                return ia != ib ? ia > ib : a.0.id < b.0.id
            }
    }
}

/// Horizontal day strip with glowing dots on days with favourite-team matches.
struct DayStrip: View {
    @Binding var offset: Int
    var highlight: Set<Int>
    @State private var showMonth = false
    var body: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: 6) {
                        HStack(spacing: 6) {
                            ForEach(-7...14, id: \.self) { o in
                                let d = Date().addingTimeInterval(Double(o) * 86400)
                                Button { withAnimation(.snappy) { offset = o } } label: {
                                    VStack(spacing: 2) {
                                        Text(o == 0 ? "اليوم" : (o == 1 ? "بكرة" : (o == -1 ? "أمس" : LocalizedStringKey(Fmt.dateLabel(d))))).font(.caption.bold())
                                        Circle().fill(highlight.contains(o) ? Color.accentColor : .clear).frame(width: 5, height: 5)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .foregroundStyle(o == offset ? Color.white : Color.primary)
                                    .glassEffect(o == offset ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
                                }
                                .buttonStyle(.plain).id(o)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onAppear { proxy.scrollTo(offset, anchor: .center) }
                .onChange(of: offset) { _, v in withAnimation { proxy.scrollTo(v, anchor: .center) } }
            }
            Button { showMonth = true } label: { Image(systemName: "calendar") }.buttonStyle(.glass)
        }
        .sheet(isPresented: $showMonth) {
            MonthPicker(offset: $offset).presentationDetents([.medium])
        }
    }
}

struct MonthPicker: View {
    @Binding var offset: Int
    @State private var date = Date()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            DatePicker("التاريخ", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical).padding()
                .navigationTitle("اختر يوم")
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("تم", systemImage: "checkmark") {
                        let cal = Calendar.current
                        offset = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
                        dismiss()
                    }.buttonStyle(.glassProminent)
                } }
        }
    }
}

/// Calendar page: day strip + favourites highlighting (scans the next 14 days' fixtures).
struct CalendarView: View {
    @Environment(AppStore.self) private var store
    @State private var offset = 0
    @State private var favDays = Set<Int>()
    @State private var list: [Fixture]?
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                DayStrip(offset: $offset, highlight: favDays)
                LoadState(value: list, error: error) { l in
                    if l.isEmpty { EmptyState(symbol: "calendar", title: "لا توجد مباريات في هذا اليوم") }
                    ForEach(MatchSort.byImportance(l)) { MatchRow(f: $0) }
                }
            }.padding()
        }
        .screenBackground()
        .navigationTitle("التقويم")
        .task(id: offset) {
            list = nil
            do { list = try await (API.shared.get("/api/fixtures?date=\(Fmt.day(offset))", maxAge: 60) as FixturesResponse).fixtures }
            catch { self.error = error.localizedDescription }
        }
        .task { await scanFavs() }
    }
    func scanFavs() async {
        let ids = Set(store.favTeams.map(\.id)); guard !ids.isEmpty else { return }
        for o in 0...7 {
            if let r: FixturesResponse = try? await API.shared.get("/api/fixtures?date=\(Fmt.day(o))", maxAge: 900),
               r.fixtures.contains(where: { ids.contains($0.home.id) || ids.contains($0.away.id) }) { favDays.insert(o) }
        }
    }
}
