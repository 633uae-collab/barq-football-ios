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
    // Scroll stability: when new events are inserted above while the user is scrolled down, keep their view in place.
    @State private var scrollPos = ScrollPosition(edge: .top)
    @State private var offsetY: CGFloat = 0
    @State private var holdPosition = false
    @State private var pendingY: CGFloat?   // last compensated offset; offsetY lags one layout pass behind scrollTo
    @State private var stabilizer = TimelineOrder.Stabilizer()   // keeps events across transiently shorter API responses
    @State private var contentH: CGFloat = 0
    @State private var replayStep = 0
    private var replay: Bool { UserDefaults.standard.bool(forKey: "replay") }
    private var refreshSeconds: Double { replay ? 6 : 15 }

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
                    case .timeline: TimelineSection(d: d, animateInsert: !holdPosition)
                    case .lineups: LineupSection(lineups: d.lineups)
                    case .stats: StatsSection(stats: d.statistics)
                    case .h2h: H2HSection(home: d.match.home.id, away: d.match.away.id)
                    case .predict: PredictionSection(fixtureId: d.match.id)
                    case .ai: MatchAISection(fixtureId: d.match.id, live: d.match.isLive)
                    }
                }.padding(.horizontal).padding(.bottom, 30)
            }
        }
        .scrollPosition($scrollPos)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in offsetY = y }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { old, new in
            contentH = new
            if holdPosition, new > old {
                // Content can grow in several layout passes (two-line names measured lazily); accumulate from the
                // last target instead of the not-yet-updated offset, otherwise later passes under-compensate.
                let target = (pendingY ?? offsetY) + (new - old)
                pendingY = target
                scrollPos.scrollTo(y: target)
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
                try? await Task.sleep(for: .seconds(refreshSeconds))
                if d?.match.isLive == true || replay { await load(); if let f = d?.match, !replay { await LiveActivities.update(f) } }
            }
        }
    }
    func load() async {
        // QA replay mode (-replay YES): steps through REAL snapshots recorded from the backend during a live match.
        let path = replay ? "/api/replay/\(fixtureId)/\(replayStep)" : "/api/match/\(fixtureId)"
        do {
            let new: MatchDetail = try await API.shared.get(path)
            if replay { replayStep += 1 }
            var merged = new
            if let old = d, old.match.id == new.match.id { merged.events = stabilizer.merge(previous: old.events, incoming: new.events) }
            // compare what is displayed (merged), not the raw response, which may be transiently shorter
            let grew = merged.events.count > (d?.events.count ?? 0) && d != nil
            pendingY = nil
            holdPosition = grew && offsetY > 260   // user is reading further down: do not yank the list
            let y0 = offsetY, h0 = contentH
            d = merged; error = nil
            if holdPosition {
                // Final exact correction once lazy rows have been measured: keep the reader's content where it was.
                try? await Task.sleep(for: .milliseconds(450))
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { scrollPos.scrollTo(y: y0 + (contentH - h0)) }
                try? await Task.sleep(for: .milliseconds(300)); holdPosition = false; pendingY = nil
            }
        } catch { if d == nil { self.error = error.localizedDescription } }
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

/// Timeline ordering: newest at top, kickoff at bottom. Sort key = elapsed, then extra, then API order (later on top).
enum TimelineOrder {
    enum Marker: String { case kickoff, ht, ft }
    enum Row: Hashable { case event(index: Int, MatchEvent), marker(Marker) }
    static let pastHT: Set<String> = ["HT", "2H", "ET", "BT", "P", "FT", "AET", "PEN"]
    static func rows(_ events: [MatchEvent], status: String) -> [Row] {
        // Same-minute ties: API-SPORTS reshuffles same-minute events between refreshes (seen in recorded real snapshots,
        // e.g. 4 half-time subs), so ties are ordered deterministically by type priority then stable key, never by array index.
        typealias K = (Int, Int, Int, String)
        var items: [(K, Row)] = events.enumerated().map { i, e in ((e.time.elapsed ?? 0, e.time.extra ?? 0, priority(e), key(e) + "|" + (e.player?.name ?? "")), .event(index: i, e)) }
        if pastHT.contains(status) {
            // HT sits above every first-half event (incl. 45+x stoppage) and below the first second-half event
            items.append(((45, 999, 0, ""), .marker(.ht)))
        }
        if Fixture.doneCodes.contains(status) { items.append(((Int.max, 0, 0, ""), .marker(.ft))) }
        let sorted = items.sorted { l, r in
            if l.0.0 != r.0.0 { return l.0.0 > r.0.0 }
            if l.0.1 != r.0.1 { return l.0.1 > r.0.1 }
            if l.0.2 != r.0.2 { return l.0.2 > r.0.2 }
            return l.0.3 > r.0.3
        }.map(\.1)
        return sorted + [.marker(.kickoff)]
    }
    /// Within one minute: goal above VAR above card above substitution.
    static func priority(_ e: MatchEvent) -> Int {
        switch e.type.lowercased() { case "goal": 4; case "var": 3; case "card": 2; case "subst": 1; default: 0 }
    }
    /// Stable identity per event: fixture-independent key of type+minute+extra+player+team (+detail),
    /// with an occurrence counter for genuine duplicates. Independent of API array position, so a refresh never re-creates rows.
    static func key(_ e: MatchEvent) -> String {
        let t = e.type.lowercased()
        // Goals/VAR: the scorer is often missing on the first report and filled in a refresh later (seen live 2026-11-02,
        // goal 69' team 21159), so the player is not part of their identity; same-slot duplicates get the #n counter.
        let who = (t == "goal" || t == "var") ? "" : (e.player?.id.map(String.init) ?? e.player?.name ?? "")
        // API-SPORTS renumbers "Substitution N" and may re-label goal details between refreshes (seen live 2026-11-02,
        // Vancouver-Seattle), so those details are excluded; subs use the outgoing player (assist) instead.
        let extra: String = switch t {
        case "subst": e.assist?.id.map(String.init) ?? e.assist?.name ?? ""
        case "goal", "var": ""   // VAR detail also changes ("" -> "Penalty confirmed") on later refreshes
        default: e.detail ?? ""
        }
        return "\(t)|\(e.time.elapsed ?? 0)|\(e.time.extra ?? 0)|\(who)|\(e.team.id)|\(extra)"
    }
    /// Keeps previously seen events across refreshes: API-SPORTS sometimes returns a transiently shorter events list.
    /// An event missing from a response is kept until it has been absent `maxMisses` consecutive responses
    /// (a genuine API revision, e.g. an event deleted after VAR); revised fields of still-present events always win.
    struct Stabilizer {
        static let maxMisses = 3
        var misses: [String: Int] = [:]
        mutating func merge(previous: [MatchEvent], incoming: [MatchEvent]) -> [MatchEvent] {
            let inKeys = Set(TimelineOrder.keyedEvents(incoming).map(\.0))
            let prevKeyed = TimelineOrder.keyedEvents(previous), prevKeys = Set(prevKeyed.map(\.0))
            // In-place revision: a new key of the same type+team replaces the missing one (e.g. goal minute corrected 10' -> 22').
            func slot(_ k: String) -> String { let p = k.split(separator: "|", omittingEmptySubsequences: false); return p.count > 4 ? "\(p[0])|\(p[4])" : k }
            var revisedSlots: [String: Int] = [:]
            for k in inKeys where !prevKeys.contains(k) { revisedSlots[slot(k), default: 0] += 1 }
            var out = incoming
            for (k, e) in prevKeyed where !inKeys.contains(k) {
                if let r = revisedSlots[slot(k)], r > 0 { revisedSlots[slot(k)] = r - 1; misses[k] = nil; continue }
                let n = misses[k, default: 0] + 1
                if n < Self.maxMisses { misses[k] = n; out.append(e) } else { misses[k] = nil }
            }
            for k in inKeys { misses[k] = nil }
            return out
        }
    }
    static func keyedEvents(_ events: [MatchEvent]) -> [(String, MatchEvent)] {
        keyed(events, status: "").compactMap { if case .event(_, let e) = $0.row { return ($0.key, e) }; return nil }
    }
    struct Keyed { let key: String; let row: Row }
    static func keyed(_ events: [MatchEvent], status: String) -> [Keyed] {
        var seen: [String: Int] = [:]
        return rows(events, status: status).map { r in
            switch r {
            case .marker(let m): return Keyed(key: "m-" + m.rawValue, row: r)
            case .event(_, let e):
                let k = key(e); let n = seen[k, default: 0]; seen[k] = n + 1
                return Keyed(key: n == 0 ? k : "\(k)#\(n)", row: r)
            }
        }
    }
}

struct TimelineSection: View {
    let d: MatchDetail
    var animateInsert = true
    var body: some View {
        if d.events.isEmpty && d.match.isUpcoming { EmptyState(symbol: "list.bullet.below.rectangle", title: "لا توجد أحداث بعد") }
        else {
            VStack(spacing: 0) {
                ForEach(TimelineOrder.keyed(d.events, status: d.match.status.short), id: \.key) { item in
                    switch item.row {
                    case .marker(let m): marker(m).accessibilityElement(children: .combine).accessibilityIdentifier("tl-\(item.key)")
                    case .event(_, let e): eventRow(e).accessibilityElement(children: .combine).accessibilityIdentifier("tl-\(item.key)")
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.vertical, 6)
            .background(alignment: .center) { Rectangle().fill(.secondary.opacity(0.35)).frame(width: 2) }
            .animation(animateInsert ? .snappy : nil, value: d.events.count)
        }
    }

    func minuteText(_ e: MatchEvent) -> String { "\(e.time.elapsed ?? 0)'" + (e.time.extra.map { "+\($0)" } ?? "") }

    @ViewBuilder func eventRow(_ e: MatchEvent) -> some View {
        let isHome = e.team.id == d.match.home.id
        HStack(spacing: 6) {
            Group { if isHome { card(e) } else { Color.clear.frame(height: 1) } }.frame(maxWidth: .infinity)
            Text(minuteText(e)).font(.caption2.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 44, height: 26).glassEffect(.regular, in: .capsule)
            Group { if isHome { Color.clear.frame(height: 1) } else { card(e) } }.frame(maxWidth: .infinity)
        }
        .padding(.vertical, 2)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder func card(_ e: MatchEvent) -> some View {
        let isSub = e.type.lowercased() == "subst"
        HStack(alignment: .top, spacing: 6) {
            if !isSub { Image(systemName: symbol(e)).foregroundStyle(color(e)).font(.subheadline) }
            VStack(alignment: .leading, spacing: 2) {
                if isSub {
                    // API-Football subst: `player` comes on, `assist` goes off (same mapping the app used before).
                    subLine(e.player?.name ?? e.team.name, inbound: true)
                    if let a = e.assist?.name { subLine(a, inbound: false) }
                } else {
                    Text(verbatim: e.player?.name ?? e.team.name).font(.caption.weight(.semibold))
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if let a = e.assist?.name { Text("صناعة: \(a)").font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                    else if e.type.lowercased() == "var", let det = e.detail { Text(verbatim: det).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    func subLine(_ name: String, inbound: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: inbound ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundStyle(inbound ? Color("BrandGreen") : .red).font(.caption)
                .accessibilityLabel(Text(inbound ? "دخول" : "خروج"))
            Text(verbatim: name).font(inbound ? .caption.weight(.semibold) : .caption2)
                .foregroundStyle(inbound ? .primary : .secondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
    }

    func marker(_ m: TimelineOrder.Marker) -> some View {
        let (title, sym): (LocalizedStringKey, String) = switch m {
        case .kickoff: ("بداية المباراة", "flag")
        case .ht: ("نهاية الشوط الأول", "pause.circle")
        case .ft: ("نهاية المباراة", "flag.checkered")
        }
        return Label(title, systemImage: sym).font(.caption.bold())
            .padding(.horizontal, 12).padding(.vertical, 5)
            .glassEffect(.regular.tint(Color("BrandGreen").opacity(0.25)), in: .capsule)
            .frame(maxWidth: .infinity).padding(.vertical, 3)
    }
    func symbol(_ e: MatchEvent) -> String {
        switch e.type.lowercased() {
        case "goal": return e.detail == "Missed Penalty" ? "xmark.circle" : "soccerball.inverse"
        case "card": return "rectangle.portrait.fill"
        case "subst": return "arrow.up.arrow.down"
        case "var": return "video.badge.checkmark"
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
                        BarMark(x: .value("p", pct(pc.draw)), y: .value("t", L.s("تعادل"))).foregroundStyle(.gray)
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
                        Text(h > a ? t.home.name : (a > h ? t.away.name : L.s("متساوي"))).bold()
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
        case "stale": return L.s("البيانات متأخرة، المحلل متوقف مؤقتاً")
        case "not_tracked": return L.s("المحلل لا يتابع هذه المباراة")
        default: return L.s("المحلل يتابع المباراة مباشرة")
        }
    }
}
