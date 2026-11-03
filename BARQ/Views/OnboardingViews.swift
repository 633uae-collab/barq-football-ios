import SwiftUI

// MARK: - Persistence (pure, unit-tested)

/// First-launch flag + applying choices to the EXISTING favorites system (AppStore.favTeams / favLeagues).
enum Onboarding {
    static let doneKey = "onboardingDone"
    static func isDone(_ d: UserDefaults = .standard) -> Bool {
        if ProcessInfo.processInfo.environment["FOTIQ_SKIP_ONBOARDING"] == "1" { return true }
        // CI screenshot harness (-screen / -qaFavTeam) opens screens directly; never block it with onboarding.
        if d.string(forKey: "screen") != nil || d.object(forKey: "qaFavTeam") != nil { return true }
        return d.bool(forKey: doneKey)
    }
    static func markDone(_ d: UserDefaults = .standard) { d.set(true, forKey: doneKey) }
    /// `-resetOnboarding YES` (UI tests / recording): fresh first-launch state.
    static func resetIfRequested(_ d: UserDefaults = .standard) {
        guard d.bool(forKey: "resetOnboarding") else { return }
        for k in [doneKey, "favTeams", "favLeagues"] { d.removeObject(forKey: k) }
    }
    /// Clubs are merged into favorites (keeps any existing ones, no duplicates).
    /// Leagues + cups replace the default league list only when the user picked at least one; skipping keeps defaults.
    static func apply(clubs: [TeamRef], leagues: [Int], cups: [Int], to store: AppStore) {
        var teams = store.favTeams
        for c in clubs where !teams.contains(where: { $0.id == c.id }) { teams.append(TeamRef(id: c.id, name: c.name, logo: c.logo)) }
        store.favTeams = teams
        var picked: [Int] = []
        for id in leagues + cups where !picked.contains(id) { picked.append(id) }
        if !picked.isEmpty { store.favLeagues = picked }
    }
}

// MARK: - Splash

/// Shown on every launch: FOTIQ mark (same asset as the launch screen) grows until it fills the screen, then fades.
struct SplashView: View {
    var onFinish: () -> Void
    @State private var scale: CGFloat = 0.55
    @State private var opacity: Double = 1
    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            Image("LaunchMark").resizable().scaledToFit().frame(width: 140, height: 140)
                .scaleEffect(scale)
                .accessibilityIdentifier("splash-logo")
        }
        .opacity(opacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("splash")
        .task {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) { scale = 1.0 }
            try? await Task.sleep(for: .seconds(0.75))
            withAnimation(.easeIn(duration: 0.9)) { scale = 14 }
            try? await Task.sleep(for: .seconds(0.6))
            withAnimation(.easeOut(duration: 0.4)) { opacity = 0 }
            try? await Task.sleep(for: .seconds(0.4))
            onFinish()
        }
    }
}

// MARK: - Onboarding flow

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    var editing = false
    var onDone: () -> Void
    @State private var step = 0
    @State private var clubs: [TeamRef] = []          // selection order preserved
    @State private var leagues: Set<Int> = []
    @State private var cups: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch step {
                case 0: ClubPickStep(selected: $clubs)
                case 1: CompetitionPickStep(kind: "League", selected: $leagues)
                default: CompetitionPickStep(kind: "Cup", selected: $cups)
                }
            }
            .frame(maxHeight: .infinity)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            footer
        }
        .background(Color("LaunchBackground").ignoresSafeArea())
        .background(LinearGradient(colors: [Color("BrandGreen").opacity(0.18), .clear], startPoint: .top, endPoint: .center).ignoresSafeArea())
        .onAppear {
            guard editing else { return }
            clubs = store.favTeams
            leagues = Set(store.favLeagues); cups = Set(store.favLeagues)
        }
    }

    var title: LocalizedStringKey { ["اختر أنديتك المفضلة", "اختر دورياتك المفضلة", "اختر بطولاتك المفضلة"][step] }
    var subtitle: LocalizedStringKey { ["اختر نادياً واحداً على الأقل", "اختياري، تقدر تتخطى", "اختياري، تقدر تتخطى"][step] }

    var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if step > 0 {
                    Button { withAnimation(.snappy) { step -= 1 } } label: { Image(systemName: "chevron.backward") }
                        .buttonStyle(.glass).accessibilityIdentifier("ob-back")
                }
                Spacer()
                Text(verbatim: (UserDefaults.standard.string(forKey: "lang") ?? "ar") == "en" ? "\(step + 1) of 3" : "\(step + 1) من 3").font(.footnote.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 12).padding(.vertical, 6).glassEffect(.regular, in: .capsule)
                    .accessibilityIdentifier("ob-progress")
            }
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i <= step ? Color("BrandGreen") : Color.white.opacity(0.18)).frame(height: 4)
                }
            }
            Text(title).font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("ob-title")
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal).padding(.top, 8).padding(.bottom, 6)
    }

    var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button { advance() } label: { Text("تخطي").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass).controlSize(.large).accessibilityIdentifier("ob-skip")
            }
            Button { advance() } label: {
                Label(step == 2 ? "ابدأ الآن" : "التالي", systemImage: step == 2 ? "checkmark" : "chevron.forward")
                    .labelStyle(.titleAndIcon).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(Color("BrandGreen")).controlSize(.large)
            .disabled(step == 0 && clubs.isEmpty)
            .accessibilityIdentifier(step == 2 ? "ob-start" : "ob-next")
        }
        .padding()
    }

    func advance() {
        if step < 2 { withAnimation(.snappy) { step += 1 }; return }
        finish()
    }
    func finish() {
        // Skip on a step = no choices from it; selections made then skipped are still honored only if made before skip.
        if editing {
            store.favTeams = clubs.map { TeamRef(id: $0.id, name: $0.name, logo: $0.logo) }
            let all = Array(leagues.union(cups))
            if !all.isEmpty { store.favLeagues = store.favLeagues.filter { all.contains($0) } + all.filter { !store.favLeagues.contains($0) } }
        } else {
            Onboarding.apply(clubs: clubs, leagues: Array(leagues), cups: Array(cups), to: store)
        }
        Onboarding.markDone()
        onDone()
    }
}

/// Real clubs: standings of the top leagues (API-Football IDs + logos via backend) + live API team search.
struct ClubPickStep: View {
    @Binding var selected: [TeamRef]
    @State private var popular: [TeamRef] = []
    @State private var results: [TeamRef] = []
    @State private var q = ""
    @State private var loading = true
    static let sources = [39, 140, 135, 78, 61, 307, 301]
    let cols = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var shown: [TeamRef] {
        let base = q.trimmingCharacters(in: .whitespaces).count >= 2 ? results : popular
        // keep chosen clubs visible at the top when not searching
        if q.isEmpty { return selected + base.filter { b in !selected.contains { $0.id == b.id } } }
        return base
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("ابحث عن نادٍ", text: $q).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("ob-search")
                if !q.isEmpty { Button { q = "" } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(.secondary) }
            }
            .padding(12).glassEffect(.regular, in: .capsule).padding(.horizontal)
            ScrollView {
                if shown.isEmpty {
                    ProgressView().padding(.top, 60).accessibilityIdentifier("ob-loading")
                }
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(shown) { t in
                        PickTile(id: "ob-club-\(t.id)", name: t.name, logo: t.logo, on: selected.contains { $0.id == t.id }) {
                            if let i = selected.firstIndex(where: { $0.id == t.id }) { selected.remove(at: i) } else { selected.append(t) }
                        }
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .task { await loadPopular() }
        .task(id: q) { await search() }
    }

    func loadPopular() async {
        while popular.isEmpty, !Task.isCancelled {
            var out: [TeamRef] = []
            await withTaskGroup(of: (Int, [TeamRef]).self) { g in
                for (i, l) in Self.sources.enumerated() {
                    g.addTask {
                        let r: StandingsResponse? = try? await API.shared.get("/api/standings/\(l)", maxAge: 3600)
                        return (i, (r?.groups.first ?? []).prefix(8).map(\.team))
                    }
                }
                var parts: [(Int, [TeamRef])] = []
                for await p in g { parts.append(p) }
                for p in parts.sorted(by: { $0.0 < $1.0 }) { for t in p.1 where !out.contains(where: { $0.id == t.id }) { out.append(t) } }
            }
            if out.isEmpty { try? await Task.sleep(for: .seconds(5)) } else { popular = out }
        }
    }
    func search() async {
        let s = q.trimmingCharacters(in: .whitespaces)
        guard s.count >= 2 else { results = []; return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled, let enc = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        var r: SearchResponse? = try? await API.shared.get("/api/search?q=\(enc)", maxAge: 300)
        var tries = 0
        while r == nil, !Task.isCancelled, tries < 6 { tries += 1; try? await Task.sleep(for: .seconds(5)); r = try? await API.shared.get("/api/search?q=\(enc)", maxAge: 300) }
        results = (r?.teams ?? []).map { TeamRef(id: $0.id, name: $0.name, logo: $0.logo) }
    }
}

/// Real leagues ("League") or cups/international competitions ("Cup") from the backend catalog.
struct CompetitionPickStep: View {
    let kind: String
    @Binding var selected: Set<Int>
    @State private var items: [LeagueMeta] = []
    @State private var q = ""
    let cols = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var shown: [LeagueMeta] {
        let s = q.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(s) || ($0.ar ?? "").contains(s) || ($0.country ?? "").localizedCaseInsensitiveContains(s) || ($0.countryAr ?? "").contains(s) }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(kind == "Cup" ? "ابحث عن بطولة" : "ابحث عن دوري", text: $q).autocorrectionDisabled()
                    .accessibilityIdentifier("ob-search")
            }
            .padding(12).glassEffect(.regular, in: .capsule).padding(.horizontal)
            ScrollView {
                if items.isEmpty { ProgressView().padding(.top, 60).accessibilityIdentifier("ob-loading") }
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(shown) { l in
                        let ar = (UserDefaults.standard.string(forKey: "lang") ?? "ar") != "en"
                        PickTile(id: "ob-comp-\(l.id)", name: ar ? l.displayName : l.name, logo: l.logo, on: selected.contains(l.id)) {
                            if selected.contains(l.id) { selected.remove(l.id) } else { selected.insert(l.id) }
                        }
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .task(id: kind) {
            items = []
            while items.isEmpty, !Task.isCancelled {
                if let c: CatalogResponse = try? await API.shared.get("/api/catalog", maxAge: 3600) {
                    let order = c.order ?? []
                    let all = c.leagues.filter { ($0.type ?? "League") == kind }
                    let ranked = all.filter { order.contains($0.id) }.sorted { (order.firstIndex(of: $0.id) ?? 0) < (order.firstIndex(of: $1.id) ?? 0) }
                    let rest = all.filter { !order.contains($0.id) && $0.active != false }.prefix(kind == "Cup" ? 40 : 30)
                    items = ranked + rest
                }
                if items.isEmpty { try? await Task.sleep(for: .seconds(5)) }
            }
        }
    }
}

struct PickTile: View {
    let id: String
    let name: String
    let logo: String?
    let on: Bool
    var toggle: () -> Void
    var body: some View {
        Button { if !on { Haptics.favoriteAdded() }; toggle() } label: {
            VStack(spacing: 8) {
                RemoteImage(url: logo, size: 52)
                Text(name).font(.footnote.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center).frame(height: 34)
                Image(systemName: on ? "star.fill" : "star").font(.title3)
                    .foregroundStyle(on ? Color("BrandGreen") : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .glassEffect(on ? .regular.tint(Color("BrandGreen").opacity(0.25)) : .regular, in: .rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(on ? Color("BrandGreen") : .clear, lineWidth: 1.5) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityValue(on ? "on" : "off")
        .accessibilityLabel(Text(name))
    }
}

/// Wraps the app: splash on every launch, onboarding on first launch only, then the unchanged app.
struct LaunchFlow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var splash = true
    @State private var onboarded = Onboarding.isDone()
    var body: some View {
        ZStack {
            if onboarded { content() } else { OnboardingView { withAnimation(.easeInOut(duration: 0.5)) { onboarded = true } }.transition(.opacity) }
            if splash { SplashView { splash = false }.transition(.opacity).zIndex(1) }
        }
    }
}
