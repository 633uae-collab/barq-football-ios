import SwiftUI
import Charts

enum MCTab: String, CaseIterable { case timeline, lineups, stats, h2h, predict, ai
    var title: LocalizedStringKey { switch self { case .timeline: "الأحداث"; case .lineups: "التشكيلة"; case .stats: "الإحصائيات"; case .h2h: "المواجهات"; case .predict: "التوقعات"; case .ai: "تحليل AI" } }
    var symbol: String { switch self { case .timeline: "list.bullet.below.rectangle"; case .lineups: "sportscourt"; case .stats: "chart.bar.xaxis"; case .h2h: "shield.lefthalf.filled"; case .predict: "chart.pie"; case .ai: "brain.head.profile" } }
}

struct MatchCenterView: View {
    let fixtureId: Int
    @Environment(AppStore.self) private var store
    @State private var d: MatchDetail?
    @State private var error: String?
    @State private var tab: MCTab = .timeline
    @State private var msg: String?

    var body: some View {
        ScrollView {
            LoadState(value: d, error: error, retry: load) { d in
                VStack(spacing: 16) {
                    Scoreboard(f: d.match)
                    GlassEffectContainer(spacing: 8) {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(MCTab.allCases, id: \.self) { t in
                                    if tab == t {
                                        Button { } label: { Label(t.title, systemImage: t.symbol).font(.subheadline) }.buttonStyle(.glassProminent)
                                    } else {
                                        Button { withAnimation(.snappy) { tab = t } } label: { Label(t.title, systemImage: t.symbol).font(.subheadline) }.buttonStyle(.glass)
                                    }
                                }
                            }.padding(.horizontal, 2)
                        }.scrollIndicators(.hidden)
                    }
                    switch tab {
                    case .timeline: TimelineSection(d: d)
                    case .lineups: LineupSection(lineups: d.lineups)
                    case .stats: StatsSection(stats: d.statistics)
                    case .h2h: H2HSection(home: d.match.home.id, away: d.match.away.id)
                    case .predict: PredictionSection(fixtureId: d.match.id)
                    case .ai: MatchAISection(fixtureId: d.match.id, live: d.match.isLive)
                    }
                }.padding(.horizontal).padding(.bottom, 30)
            }
        }
        .screenBackground()
        .navigationTitle(d.map { "\($0.match.home.name) × \($0.match.away.name)" } ?? "المباراة")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let f = d?.match {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { store.toggleSaved(f.id) } label: { Image(systemName: store.savedMatches.contains(f.id) ? "bookmark.fill" : "bookmark") }
                    Menu {
                        if f.isUpcoming { Button("أضف لتقويم الآيفون", systemImage: "calendar.badge.plus") { Task { do { try await CalendarService.add(f); msg = "تمت الإضافة للتقويم" } catch { msg = error.localizedDescription } } } }
                        if !f.isDone { Button("تابع على شاشة القفل", systemImage: "platter.filled.bottom.iphone") { do { try LiveActivities.start(for: f); msg = "بدأت المتابعة المباشرة" } catch { msg = error.localizedDescription } } }
                        Button("تفعيل تنبيهات المحلل", systemImage: "bell.badge") { Task { _ = await Notifier.requestPermission() } }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
        }
        .alert(msg ?? "", isPresented: Binding(get: { msg != nil }, set: { if !$0 { msg = nil } })) { Button("تم") {} }
        .barqDestinations()
        .task { await load() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if d?.match.isLive == true { await load(); if let f = d?.match { await LiveActivities.update(f) } }
            }
        }
    }
    func load() async {
        do { d = try await API.shared.get("/api/match/\(fixtureId)"); error = nil } catch { self.error = error.localizedDescription }
    }
}

struct Scoreboard: View {
    let f: Fixture
    var body: some View {
        VStack(spacing: 14) {
            NavigationLink(value: Route.league(f.league.id)) {
                HStack { RemoteImage(url: f.league.logo, fallback: "trophy", size: 22); Text(f.league.name).font(.caption.bold()); if let r = f.league.round { Text(r).font(.caption).foregroundStyle(.secondary) } }
            }.buttonStyle(.plain)
            HStack(alignment: .top) {
                team(f.home)
                VStack(spacing: 8) {
                    Text(f.isUpcoming ? Fmt.time(f.kickoff) : f.scoreText).font(.system(size: 44, weight: .heavy, design: .rounded)).monospacedDigit()
                        .environment(\.layoutDirection, .leftToRight).contentTransition(.numericText())
                    StatusBadge(f: f)
                    Text(Fmt.dateLabel(f.kickoff)).font(.caption2).foregroundStyle(.secondary)
                }
                team(f.away)
            }
            HStack(spacing: 14) {
                if let v = f.venue { Label(v, systemImage: "sportscourt") }
                if let r = f.referee { Label(r, systemImage: "whistle") }
            }.font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
    }
    func team(_ t: TeamRef) -> some View {
        NavigationLink(value: Route.team(t.id)) {
            VStack(spacing: 8) { RemoteImage(url: t.logo, size: 70); Text(t.name).font(.subheadline.bold()).multilineTextAlignment(.center) }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
    }
}

struct TimelineSection: View {
    let d: MatchDetail
    var body: some View {
        if d.events.isEmpty { EmptyState(symbol: "list.bullet.below.rectangle", title: "لا توجد أحداث بعد") }
        else {
            VStack(spacing: 8) {
                ForEach(Array(d.events.enumerated()), id: \.offset) { _, e in
                    let isHome = e.team.id == d.match.home.id
                    HStack {
                        if !isHome { Spacer() }
                        HStack(spacing: 8) {
                            Text("\(e.time.elapsed ?? 0)'" + (e.time.extra.map { "+\($0)" } ?? "")).font(.caption.bold()).monospacedDigit().frame(width: 40)
                            Image(systemName: symbol(e)).foregroundStyle(color(e))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.player?.name ?? "").font(.subheadline.weight(.semibold))
                                if let a = e.assist?.name { Text(e.type == "subst" ? "خروج: \(a)" : "صناعة: \(a)").font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                        .padding(10).glassEffect(.regular, in: .rect(cornerRadius: 14))
                        if isHome { Spacer() }
                    }
                }
            }
        }
    }
    func symbol(_ e: MatchEvent) -> String {
        switch e.type.lowercased() {
        case "goal": return e.detail == "Missed Penalty" ? "xmark.circle" : "soccerball.inverse"
        case "card": return "rectangle.portrait.fill"
        case "subst": return "arrow.up.arrow.down"
        case "var": return "tv"
        default: return "circle"
        }
    }
    func color(_ e: MatchEvent) -> Color {
        if e.type.lowercased() == "card" { return (e.detail ?? "").contains("Red") ? .red : .yellow }
        if e.type.lowercased() == "goal" { return .green }
        return .secondary
    }
}

/// Lineup drawn on a native pitch using API-Football grid "row:col".
struct LineupSection: View {
    let lineups: [Lineup]
    @State private var side = 0
    var body: some View {
        if lineups.count < 2 { EmptyState(symbol: "sportscourt", title: "التشكيلة لم تُعلن بعد", message: "تظهر عادة قبل المباراة بساعة") }
        else {
            VStack(spacing: 12) {
                Picker("الفريق", selection: $side) { Text(lineups[0].team.name).tag(0); Text(lineups[1].team.name).tag(1) }.pickerStyle(.segmented)
                let l = lineups[side]
                HStack { RemoteImage(url: l.team.logo, size: 24); Text(l.formation ?? "").font(.headline.monospacedDigit()); Spacer(); if let c = l.coach?.name { Label(c, systemImage: "person.crop.square").font(.caption) } }
                Pitch(players: l.startXI.map(\.player)).frame(height: 440)
                if let subs = l.substitutes, !subs.isEmpty {
                    SectionHeader(title: "الاحتياط", symbol: "arrow.up.arrow.down")
                    ForEach(subs, id: \.player.name) { s in
                        HStack { Text(s.player.number.map(String.init) ?? "-").monospacedDigit().frame(width: 28); Text(s.player.name); Spacer(); Text(s.player.pos ?? "").foregroundStyle(.secondary) }.font(.subheadline)
                    }
                }
            }
        }
    }
}

struct Pitch: View {
    let players: [LineupPlayer.P]
    var body: some View {
        GeometryReader { g in
            let rows = players.compactMap { Int($0.grid?.split(separator: ":").first ?? "") }.max() ?? 5
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(LinearGradient(colors: [.green.opacity(0.55), .green.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.5), lineWidth: 2).padding(6)
                Rectangle().fill(.white.opacity(0.5)).frame(height: 2)
                Circle().stroke(.white.opacity(0.5), lineWidth: 2).frame(width: 80)
                ForEach(players, id: \.name) { p in
                    let parts = (p.grid ?? "").split(separator: ":").compactMap { Int($0) }
                    if parts.count == 2 {
                        let r = parts[0], c = parts[1]
                        let inRow = players.filter { ($0.grid ?? "").hasPrefix("\(r):") }.count
                        let y = g.size.height * (1 - (CGFloat(r) - 0.5) / CGFloat(rows))
                        let x = g.size.width * (CGFloat(c) - 0.5) / CGFloat(max(inRow, 1))
                        VStack(spacing: 2) {
                            Text(p.number.map(String.init) ?? "").font(.caption.bold()).frame(width: 30, height: 30)
                                .glassEffect(.regular.tint(.blue.opacity(0.5)), in: .circle)
                            Text(p.name.split(separator: " ").last.map(String.init) ?? p.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        }.position(x: x, y: y)
                    }
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct StatsSection: View {
    let stats: [TeamStats]
    var body: some View {
        if stats.count < 2 { EmptyState(symbol: "chart.bar.xaxis", title: "لا توجد إحصائيات بعد") }
        else {
            VStack(spacing: 12) {
                HStack { RemoteImage(url: stats[0].team.logo, size: 26); Spacer(); RemoteImage(url: stats[1].team.logo, size: 26) }
                ForEach(stats[0].statistics, id: \.type) { s in
                    let a = s.value?.number ?? 0
                    let b = stats[1].statistics.first { $0.type == s.type }?.value?.number ?? 0
                    VStack(spacing: 4) {
                        HStack { Text(s.value?.text ?? "0"); Spacer(); Text(StatName.ar(s.type)).foregroundStyle(.secondary); Spacer(); Text(stats[1].statistics.first { $0.type == s.type }?.value?.text ?? "0") }
                            .font(.caption.monospacedDigit())
                        GeometryReader { g in
                            let tot = max(a + b, 0.0001)
                            HStack(spacing: 2) {
                                Capsule().fill(Color.accentColor).frame(width: g.size.width * a / tot)
                                Capsule().fill(Color.secondary.opacity(0.5))
                            }
                        }.frame(height: 6)
                    }
                }
            }
            .padding().glassEffect(.regular, in: .rect(cornerRadius: 22))
            .environment(\.layoutDirection, .leftToRight)
        }
    }
}

enum StatName {
    static let map: [String: String] = ["Shots on Goal": "تسديدات على المرمى", "Shots off Goal": "تسديدات خارج المرمى", "Total Shots": "التسديدات", "Blocked Shots": "تسديدات مصدودة",
        "Shots insidebox": "تسديدات داخل الصندوق", "Shots outsidebox": "تسديدات خارج الصندوق", "Fouls": "الأخطاء", "Corner Kicks": "الركنيات", "Offsides": "التسلل",
        "Ball Possession": "الاستحواذ", "Yellow Cards": "بطاقات صفراء", "Red Cards": "بطاقات حمراء", "Goalkeeper Saves": "تصديات الحارس", "Total passes": "التمريرات",
        "Passes accurate": "تمريرات دقيقة", "Passes %": "دقة التمرير", "expected_goals": "الأهداف المتوقعة xG", "goals_prevented": "أهداف منعها الحارس"]
    static func ar(_ k: String) -> String { (UserDefaults.standard.string(forKey: "lang") ?? "ar") == "en" ? k : (map[k] ?? k) }
}

struct H2HSection: View {
    let home: Int, away: Int
    @State private var list: [Fixture]?
    @State private var error: String?
    var body: some View {
        LoadState(value: list, error: error) { l in
            if l.isEmpty { EmptyState(symbol: "shield.lefthalf.filled", title: "لا توجد مواجهات سابقة") }
            else {
                let hw = l.filter { ($0.home.id == home && $0.home.winner == true) || ($0.away.id == home && $0.away.winner == true) }.count
                let aw = l.filter { ($0.home.id == away && $0.home.winner == true) || ($0.away.id == away && $0.away.winner == true) }.count
                HStack { stat(hw, "فوز"); stat(l.count - hw - aw, "تعادل"); stat(aw, "فوز") }
                ForEach(l) { MatchRow(f: $0) }
            }
        }
        .task { do { list = try await (API.shared.get("/api/h2h/\(home)/\(away)") as FixtureList).fixtures } catch { self.error = error.localizedDescription } }
    }
    func stat(_ n: Int, _ t: LocalizedStringKey) -> some View {
        VStack { Text("\(n)").font(.title.bold()); Text(t).font(.caption) }.frame(maxWidth: .infinity).padding(10).glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

struct PredictionSection: View {
    let fixtureId: Int
    @State private var p: Prediction?
    @State private var error: String?
    var body: some View {
        LoadState(value: p, error: error) { p in
            if let pc = p.percent, let t = p.teams {
                VStack(alignment: .leading, spacing: 14) {
                    Label("احتمالات تقديرية للفوز (API-SPORTS)", systemImage: "chart.pie").font(.headline)
                    Text("تقدير إحصائي وليس نتيجة مؤكدة").font(.caption).foregroundStyle(.secondary)
                    Chart {
                        BarMark(x: .value("p", pct(pc.home)), y: .value("t", t.home.name)).foregroundStyle(.blue)
                        BarMark(x: .value("p", pct(pc.draw)), y: .value("t", String(localized: "تعادل"))).foregroundStyle(.gray)
                        BarMark(x: .value("p", pct(pc.away)), y: .value("t", t.away.name)).foregroundStyle(.purple)
                    }
                    .chartXScale(domain: 0...100).frame(height: 140)
                    if let a = p.advice { Label("نصيحة تقديرية: \(a)", systemImage: "lightbulb").font(.callout) }
                    WhyList(p: p)
                }.padding().glassEffect(.regular, in: .rect(cornerRadius: 22))
            } else { EmptyState(symbol: "chart.pie", title: "لا يوجد توقع لهذه المباراة") }
        }
        .task { do { p = try await API.shared.get("/api/predictions/\(fixtureId)", maxAge: 3600) } catch { self.error = error.localizedDescription } }
    }
    func pct(_ s: String?) -> Double { Double((s ?? "0").replacingOccurrences(of: "%", with: "")) ?? 0 }
}

/// Explains the prediction using the comparison block (form, attack, defence, h2h...).
struct WhyList: View {
    let p: Prediction
    static let names: [String: String] = ["form": "الفورمة", "att": "الهجوم", "def": "الدفاع", "poisson_distribution": "توزيع بواسون", "h2h": "المواجهات", "goals": "الأهداف", "total": "المجموع"]
    var body: some View {
        if let c = p.comparison, let t = p.teams {
            VStack(alignment: .leading, spacing: 6) {
                Label("ليش؟", systemImage: "text.magnifyingglass").font(.subheadline.bold())
                ForEach(c.keys.sorted(), id: \.self) { k in
                    let h = Double((c[k]?.home ?? "0").replacingOccurrences(of: "%", with: "")) ?? 0
                    let a = Double((c[k]?.away ?? "0").replacingOccurrences(of: "%", with: "")) ?? 0
                    HStack {
                        Text(Self.names[k] ?? k).frame(width: 90, alignment: .leading)
                        Text(h > a ? t.home.name : (a > h ? t.away.name : String(localized: "متساوي"))).bold()
                        Spacer()
                        Text("\(Int(h))% - \(Int(a))%").monospacedDigit().foregroundStyle(.secondary)
                    }.font(.caption)
                }
            }
        }
    }
}

struct MatchAISection: View {
    let fixtureId: Int
    let live: Bool
    @State private var r: InsightsResponse?
    @State private var error: String?
    var body: some View {
        LoadState(value: r, error: error) { r in
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "brain.head.profile").foregroundStyle(.cyan)
                    Text(statusText(r)).font(.subheadline)
                    Spacer()
                }.padding().glassEffect(.regular, in: .rect(cornerRadius: 18))
                if r.insights.isEmpty { EmptyState(symbol: "waveform.path.ecg", title: "المحلل يجمع البيانات", message: "يحتاج ٨ دقائق من الإحصائيات المباشرة قبل أي تحليل") }
                ForEach(r.insights) { InsightCard(insight: $0) }
            }
        }
        .task {
            while !Task.isCancelled {
                do { r = try await API.shared.get("/api/insights/\(fixtureId)"); error = nil } catch { self.error = error.localizedDescription }
                if !live { break }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
    func statusText(_ r: InsightsResponse) -> String {
        switch r.status {
        case "stale": return String(localized: "البيانات متأخرة، المحلل متوقف مؤقتاً")
        case "not_tracked": return String(localized: "المحلل لا يتابع هذه المباراة")
        default: return String(localized: "المحلل يتابع المباراة مباشرة")
        }
    }
}
