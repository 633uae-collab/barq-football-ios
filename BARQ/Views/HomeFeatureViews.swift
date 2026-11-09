import SwiftUI

/// Fixed height shared by every hero state so the top card never changes size.
let heroHeight: CGFloat = 206

/// TOP: favorite matches that are live or start within 60 min. One full-size match per page, swipe like iOS pages.
/// Selection is keyed by fixture id, so a refresh never jumps back to the first match.
struct FavoritesHero: View {
    let matches: [Fixture]
    let lineupsReady: Set<Int>
    var onAdd: () -> Void
    @State private var selected: Int?

    var body: some View {
        VStack(spacing: 10) {
            if matches.isEmpty {
                HeroEmpty(onAdd: onAdd)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(matches) { f in
                            FavoriteHeroCard(f: f, lineupsReady: lineupsReady.contains(f.id), hasPager: matches.count > 1)
                                .overlay(alignment: .bottom) {
                                    if matches.count > 1 { pager.padding(.bottom, 8) }
                                }
                                .containerRelativeFrame(.horizontal)
                                .id(f.id)
                        }
                    }.scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $selected)
                .scrollIndicators(.hidden)
                .frame(height: heroHeight)
                .accessibilityIdentifier("home-hero")
                .accessibilityValue(Text(verbatim: "\(selected ?? matches[0].id)"))

            }
        }
        .onAppear { selected = HomeFeed.keepSelection(selected, in: matches.map(\.id)) }
        .onChange(of: matches.map(\.id)) { _, ids in selected = HomeFeed.keepSelection(selected, in: ids) }
    }
    var pager: some View {
        HStack(spacing: 6) {
            ForEach(matches) { f in
                let on = f.id == (selected ?? matches.first?.id)
                Button { withAnimation(.smooth) { selected = f.id } } label: {
                    Capsule().fill(on ? Color.accentColor : Color.white.opacity(0.25))
                        .frame(width: on ? 14 : 5, height: 5)
                        .frame(minWidth: 24, minHeight: 24)
                }.buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: "\(f.home.name) - \(f.away.name)"))
            }
        }.accessibilityIdentifier("hero-dots")
    }

}

private struct HeroBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity).frame(height: heroHeight)
            .background {
                ZStack {
                    LinearGradient(colors: [.green.opacity(0.35), .blue.opacity(0.35), .black.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "sportscourt").resizable().scaledToFit().foregroundStyle(.white.opacity(0.06)).padding(10)
                }.clipShape(.rect(cornerRadius: 28))
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
            .padding(.horizontal, 2)
    }
}

struct HeroEmpty: View {
    var onAdd: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.circle").font(.system(size: 34)).foregroundStyle(Color.accentColor)
            Text("لا توجد مباريات مباشرة حالياً").font(.headline).multilineTextAlignment(.center)
            Button(action: onAdd) {
                Label("إضافة مباريات", systemImage: "plus").font(.subheadline.bold())
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent).tint(Color.accentColor)
            .accessibilityIdentifier("hero-add")
        }
        .modifier(HeroBackground())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hero-empty")
    }
}

struct FavoriteHeroCard: View {
    let f: Fixture
    let lineupsReady: Bool
    var hasPager = false
    var body: some View {
        VStack(spacing: 8) {
            NavigationLink(value: Route.match(f.id)) {
                VStack(spacing: 8) {
                    HStack {
                        RemoteImage(url: f.league.logo, fallback: "trophy", size: 20)
                        Text(f.league.name).font(.caption.weight(.semibold)).lineLimit(1)
                        Spacer()
                        if f.isLive {
                            Label("مباشر", systemImage: "dot.radiowaves.left.and.right").font(.caption.bold()).foregroundStyle(.red)
                                .padding(.horizontal, 8).padding(.vertical, 3).glassEffect(.regular, in: .capsule)
                                .accessibilityIdentifier("hero-live-badge")
                        }
                    }
                    HStack(alignment: .top) {
                        team(f.home)
                        center.frame(minWidth: 110)
                        team(f.away)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hero-page-\(f.id)")
            Spacer(minLength: 0)
            if !f.isLive {
                if lineupsReady {
                    NavigationLink(value: Route.match(f.id)) {
                        Label("عرض التشكيلة", systemImage: "sportscourt").font(.caption.bold())
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("hero-lineups")
                } else {
                    Text("التشكيلة لم تُعلن بعد").font(.caption2).foregroundStyle(.secondary)
                        .accessibilityIdentifier("hero-no-lineups")
                }
            }
        }
        .padding(.bottom, hasPager ? 24 : 0)
        .modifier(HeroBackground())
    }

    func team(_ t: TeamRef) -> some View {
        VStack(spacing: 6) {
            RemoteImage(url: t.logo, size: 52)
            Text(verbatim: t.name).font(.subheadline.bold()).lineLimit(2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity)
    }

    @ViewBuilder var center: some View {
        if f.isLive {
            VStack(spacing: 6) {
                FixtureScore(f: f).font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit()
                    .accessibilityIdentifier("hero-score")
                LivePill(minute: f.status.elapsed, extra: f.status.extra, status: f.status.short)
            }
        } else {
            VStack(spacing: 4) {
                // Per-second countdown for users. Under UI tests (FOTIQ_UI_TEST=1) it ticks every 30 s: a 1 s re-render of the glass hero
                // kept the app from ever going idle for XCUITest when a favourite kicked off within the hero window (same issue as LivePill).
                TimelineView(.periodic(from: .now, by: HomeFeed.uiTest ? 30 : 1)) { ctx in
                    Text(verbatim: HomeFeed.countdown(to: f.kickoff, now: ctx.date))
                        .font(.system(size: 28, weight: .heavy, design: .rounded)).monospacedDigit()
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityIdentifier("hero-countdown")
                }
                Text("على البداية").font(.caption2).foregroundStyle(.secondary)
                Label(HomeFeed.uaeTime(f.kickoff), systemImage: "clock").font(.caption.bold())
                Text("بتوقيت الإمارات").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// MIDDLE: FOTIQ STARS — one real standout player at a time, auto-advance every 5 s while Home is visible.
struct StarsCard: View {
    let players: [StarPlayer]?
    let active: Bool
    @State private var selected: Int?
    @State private var holdUntil = Date.distantPast

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "star.circle.fill").foregroundStyle(Color.accentColor)
                BrandHeading(title: "نجوم الملاعب")
                Spacer()
            }
            if let p = players, !p.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(p) { s in
                            NavigationLink(value: Route.player(s.id)) { StarRow(s: s) }
                                .buttonStyle(.plain)
                                .containerRelativeFrame(.horizontal)
                                .id(s.id)
                                .accessibilityIdentifier("star-player-\(s.id)")
                        }
                    }.scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $selected)
                .scrollIndicators(.hidden)
                .frame(height: 76)
                .simultaneousGesture(DragGesture().onChanged { _ in holdUntil = Date().addingTimeInterval(8) })
                .accessibilityIdentifier("stars-pager")
                .accessibilityValue(Text(verbatim: "\(selected ?? p[0].id)"))
                HStack(spacing: 6) {
                    Spacer()
                    ForEach(p) { s in
                        Capsule().fill(s.id == (selected ?? p[0].id) ? Color.accentColor : Color.white.opacity(0.25))
                            .frame(width: s.id == (selected ?? p[0].id) ? 14 : 5, height: 5)
                    }
                    Spacer()
                }
            } else if players != nil {
                Label("لا توجد بيانات لاعبين لمباريات اليوم بعد", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 60)
                    .accessibilityIdentifier("stars-empty")
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .padding(14)
        .background(LinearGradient(colors: [Color(red: 0.05, green: 0.09, blue: 0.2), Color(red: 0.03, green: 0.06, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stars-card")
        .onChange(of: players?.map(\.id) ?? []) { _, ids in selected = HomeFeed.keepSelection(selected, in: ids) }
        // Auto-advance only while Home is on screen and the app is active (task cancels otherwise).
        .task(id: active && (players?.count ?? 0) > 1) {
            guard active, let p = players, p.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                if Date() < holdUntil { continue }
                withAnimation(.smooth) { selected = HomeFeed.nextStar(selected ?? p[0].id, in: p.map(\.id)) }
            }
        }
    }
}

struct StarRow: View {
    let s: StarPlayer
    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: s.photo.flatMap(URL.init(string:))) { img in img.resizable().scaledToFill() } placeholder: {
                    Image(systemName: "person.fill").foregroundStyle(.secondary)
                }
                .frame(width: 60, height: 60).clipShape(.circle)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                RemoteImage(url: s.team.logo, size: 22).background(Circle().fill(.black.opacity(0.6)).frame(width: 26, height: 26))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: s.name).font(.subheadline.bold()).lineLimit(1)
                Text(verbatim: s.team.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 12) {
                if let r = s.rating { stat(String(format: "%.1f", r), "التقييم") }
                stat("\(s.goals)", "أهداف")
                stat("\(s.assists)", "صناعة")
            }
        }
        .padding(.horizontal, 2)
        .contentShape(.rect)
    }
    func stat(_ v: String, _ k: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: v).font(.headline).monospacedDigit().foregroundStyle(Color.accentColor)
            Text(k).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// BOTTOM: upcoming match card in the existing MatchRow style + date, UAE time and a favorite star.
struct UpcomingRow: View {
    let f: Fixture
    @Environment(AppStore.self) private var store
    var body: some View {
        let starred = store.savedMatches.contains(f.id)
        ZStack(alignment: .topLeading) {
            NavigationLink(value: Route.match(f.id)) {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        RemoteImage(url: f.league.logo, fallback: "trophy", size: 16)
                        Text(f.league.name).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                    }.padding(.horizontal, 44)
                    HStack(spacing: 10) {
                        teamCol(f.home)
                        VStack(spacing: 3) {
                            Text(HomeFeed.uaeTime(f.kickoff)).font(.headline).monospacedDigit()
                            Text(HomeFeed.uaeDate(f.kickoff)).font(.caption2).foregroundStyle(.secondary)
                        }.frame(width: 92)
                        teamCol(f.away)
                    }
                }
                .padding(.vertical, 12).padding(.horizontal, 10)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("upcoming-row-\(f.id)")
            .accessibilityValue(Text(verbatim: "\(f.ts)"))
            Button { withAnimation(.snappy) { store.toggleSaved(f.id) } } label: {
                Image(systemName: starred ? "star.fill" : "star").font(.body.bold())
                    .foregroundStyle(starred ? Color.accentColor : .secondary)
                    .frame(width: 44, height: 44).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(starred ? "إزالة من المفضلة" : "إضافة للمفضلة"))
            .accessibilityValue(Text(verbatim: starred ? "on" : "off"))
            .accessibilityIdentifier("upcoming-star-\(f.id)")
        }
    }
    func teamCol(_ t: TeamRef) -> some View {
        VStack(spacing: 6) {
            RemoteImage(url: t.logo, size: 38)
            Text(t.name).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity)
    }
}

/// "+ إضافة مباريات": pick matches, clubs and competitions from real loaded fixtures; saved in AppStore (UserDefaults + server prefs).
struct AddFavoritesSheet: View {
    let fixtures: [Fixture]
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var q = ""
    var body: some View {
        NavigationStack {
            List {
                Picker("", selection: $tab) {
                    Text("المباريات").tag(0); Text("الأندية").tag(1); Text("البطولات").tag(2)
                }.pickerStyle(.segmented).listRowBackground(Color.clear)
                switch tab {
                case 0:
                    ForEach(matches) { f in
                        toggleRow(on: store.savedMatches.contains(f.id), id: "pick-match-\(f.id)") { store.toggleSaved(f.id) } label: {
                            HStack(spacing: 8) {
                                RemoteImage(url: f.home.logo, size: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: "\(f.home.name) - \(f.away.name)").font(.subheadline).lineLimit(1)
                                    Text(verbatim: "\(f.league.name) · \(HomeFeed.uaeDate(f.kickoff)) \(HomeFeed.uaeTime(f.kickoff))").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                RemoteImage(url: f.away.logo, size: 24)
                            }
                        }
                    }
                case 1:
                    ForEach(teams) { t in
                        toggleRow(on: store.isFav(team: t.id), id: "pick-team-\(t.id)") { store.toggleFav(t) } label: {
                            HStack { RemoteImage(url: t.logo, size: 26); Text(verbatim: t.name) }
                        }
                    }
                default:
                    ForEach(leagues, id: \.id) { l in
                        toggleRow(on: store.favLeagues.contains(l.id), id: "pick-league-\(l.id)") { store.toggleLeague(l.id) } label: {
                            HStack { RemoteImage(url: l.logo, fallback: "trophy", size: 26); Text(verbatim: l.name) }
                        }
                    }
                }
            }
            .searchable(text: $q)
            .navigationTitle("إضافة مباريات")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم", systemImage: "checkmark") { dismiss() }.buttonStyle(.glassProminent).accessibilityIdentifier("pick-done") } }
        }
    }
    func match(_ s: String) -> Bool { q.isEmpty || s.localizedCaseInsensitiveContains(q) }
    var matches: [Fixture] {
        HomeFeed.dedupe(fixtures).filter { !$0.isDone && match("\($0.home.name) \($0.away.name) \($0.league.name)") }.sorted { $0.ts != $1.ts ? $0.ts < $1.ts : $0.id < $1.id }
    }
    var teams: [TeamRef] {
        var seen = Set<Int>()
        return fixtures.flatMap { [$0.home, $0.away] }.filter { seen.insert($0.id).inserted && match($0.name) }.sorted { $0.name < $1.name }
    }
    var leagues: [LeagueRef] {
        var seen = Set<Int>()
        return fixtures.map(\.league).filter { seen.insert($0.id).inserted && match($0.name) }
    }
    func toggleRow<L: View>(on: Bool, id: String, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            HStack { label(); Image(systemName: on ? "star.fill" : "star").foregroundStyle(on ? Color.accentColor : .secondary) }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(verbatim: on ? "on" : "off"))
        .accessibilityIdentifier(id)
    }
}
