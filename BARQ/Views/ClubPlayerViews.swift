import SwiftUI
import Charts

struct ClubView: View {
    let teamId: Int
    @Environment(AppStore.self) private var store
    @State private var t: TeamResponse?
    @State private var error: String?
    var body: some View {
        ScrollView {
            LoadState(value: t, error: error, retry: { await load() }) { t in
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        RemoteImage(url: t.team?.logo, size: 96)
                        Text(t.team?.name ?? "").font(.title.bold())
                        HStack(spacing: 14) {
                            if let c = t.team?.country { Label(c, systemImage: "flag") }
                            if let y = t.team?.founded { Label(String(y), systemImage: "calendar") }
                            if let v = t.venue?.name { Label(v, systemImage: "sportscourt") }
                        }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        GlassEffectContainer(spacing: 10) {
                            HStack {
                                if let team = t.team {
                                    Button(store.isFav(team: team.id) ? "في المفضلة" : "أضف للمفضلة", systemImage: store.isFav(team: team.id) ? "star.fill" : "star") {
                                        store.toggleFav(TeamRef(id: team.id, name: team.name, logo: team.logo))
                                    }.buttonStyle(.glassProminent)
                                    Button(store.mutedTeams.contains(team.id) ? "الإشعارات مكتومة" : "الإشعارات مفعلة", systemImage: store.mutedTeams.contains(team.id) ? "bell.slash" : "bell") {
                                        if let i = store.mutedTeams.firstIndex(of: team.id) { store.mutedTeams.remove(at: i) } else { store.mutedTeams.append(team.id) }
                                    }.buttonStyle(.glass)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 22)
                    .glassEffect(.regular.tint(.blue.opacity(0.12)), in: .rect(cornerRadius: 30))

                    if let n = t.next, !n.isEmpty { SectionHeader(title: "المباريات القادمة", symbol: "clock"); ForEach(n) { MatchRow(f: $0) } }
                    if let l = t.last, !l.isEmpty { SectionHeader(title: "آخر النتائج", symbol: "flag.checkered"); ForEach(l) { MatchRow(f: $0) } }
                    if let s = t.squad, !s.isEmpty {
                        SectionHeader(title: "اللاعبون", symbol: "person.3")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 10) {
                            ForEach(s) { p in
                                NavigationLink(value: Route.player(p.id)) {
                                    VStack(spacing: 4) {
                                        RemoteImage(url: p.photo, fallback: "person.crop.circle", size: 56, circle: true)
                                        Text(p.name).font(.caption2.bold()).lineLimit(1)
                                        Text("\(p.number.map(String.init) ?? "-") · \(p.pos ?? "")").font(.caption2).foregroundStyle(.secondary)
                                    }.padding(8).frame(maxWidth: .infinity).glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if let tr = t.transfers, !tr.isEmpty {
                        SectionHeader(title: "الانتقالات", symbol: "arrow.left.arrow.right")
                        ForEach(tr.indices, id: \.self) { i in
                            let x = tr[i]
                            HStack(spacing: 8) {
                                RemoteImage(url: x.out.logo, size: 24)
                                Image(systemName: "arrow.forward")
                                RemoteImage(url: x.in.logo, size: 24)
                                Text(x.player.name ?? "").font(.subheadline.bold()).lineLimit(1)
                                Spacer()
                                VStack(alignment: .trailing) { Text(x.date ?? "").font(.caption2.monospacedDigit()); Text(x.type ?? "").font(.caption2).foregroundStyle(.secondary) }
                            }.padding(10).glassEffect(.regular, in: .rect(cornerRadius: 14))
                        }
                    }
                }.padding(.horizontal).padding(.bottom, 30)
            }
        }
        .screenBackground()
        .navigationTitle(t?.team?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        // Keeps retrying every 5 s while visible (task is cancelled on disappear) so a tunnel rotation self-heals.
        .task { while t == nil, !Task.isCancelled { await load(); if t == nil { try? await Task.sleep(for: .seconds(5)) } } }
    }
    func load() async {
        do { t = try await API.shared.get("/api/team/\(teamId)", maxAge: 600); error = nil } catch { self.error = error.localizedDescription }
    }
}

struct PlayerView: View {
    let playerId: Int
    @State private var r: PlayerResponse?
    @State private var error: String?
    var body: some View {
        ScrollView {
            LoadState(value: r, error: error) { r in
                if let p = r.player {
                    VStack(spacing: 16) {
                        VStack(spacing: 8) {
                            RemoteImage(url: p.photo, fallback: "person.crop.circle", size: 110, circle: true)
                            Text(p.name).font(.title.bold())
                            HStack(spacing: 14) {
                                if let n = p.nationality { Label(n, systemImage: "flag") }
                                if let a = p.age { Label("\(a)", systemImage: "birthday.cake") }
                                if let h = p.height { Label(h, systemImage: "ruler") }
                            }.font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 20).glassEffect(.regular, in: .rect(cornerRadius: 30))
                        ForEach(r.stats ?? [], id: \.self) { s in StatBlock(s: s) }
                        if (r.stats ?? []).isEmpty { EmptyState(symbol: "chart.bar", title: "لا توجد إحصائيات للموسم") }
                    }.padding(.horizontal).padding(.bottom, 30)
                } else { EmptyState(symbol: "person.crop.circle.badge.questionmark", title: "اللاعب غير موجود") }
            }
        }
        .screenBackground()
        .navigationTitle(r?.player?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while r == nil, !Task.isCancelled {
                do { r = try await API.shared.get("/api/player/\(playerId)", maxAge: 600); error = nil }
                catch { self.error = error.localizedDescription; try? await Task.sleep(for: .seconds(5)) }
            }
        }
    }
}

struct StatBlock: View {
    let s: PlayerSeasonStat
    var items: [(String, Int)] { [("أهداف", s.goals), ("صناعة", s.assists), ("تسديد", s.shots), ("على المرمى", s.sot), ("مراوغات", s.dribbles), ("قطع", s.tackles), ("تمريرات مفتاحية", s.keyPasses)] }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { RemoteImage(url: s.league.logo, fallback: "trophy", size: 22); Text(s.league.name ?? "").font(.subheadline.bold()); Spacer(); RemoteImage(url: s.team.logo, size: 22) }
            HStack {
                stat("\(s.apps ?? 0)", "مباريات", "sportscourt"); stat("\(s.minutes ?? 0)", "دقائق", "stopwatch")
                stat(s.rating.flatMap { Double($0) }.map { String(format: "%.1f", $0) } ?? "-", "تقييم", "star")
            }
            Chart(items.indices, id: \.self) { idx in
                let it = items[idx]
                BarMark(x: .value("v", it.1), y: .value("k", it.0)).foregroundStyle(Color.accentColor.gradient)
                    .annotation(position: .trailing) { Text("\(it.1)").font(.caption2) }
            }.frame(height: 200)
            HStack { Label("\(s.yellow)", systemImage: "rectangle.portrait.fill").foregroundStyle(.yellow); Label("\(s.red)", systemImage: "rectangle.portrait.fill").foregroundStyle(.red) }.font(.caption)
        }.padding().glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
    func stat(_ v: String, _ t: LocalizedStringKey, _ sym: String) -> some View {
        VStack(spacing: 2) { Image(systemName: sym).foregroundStyle(.secondary); Text(v).font(.headline.monospacedDigit()); Text(t).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
    }
}
