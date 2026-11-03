import SwiftUI
import os

/// Splash diagnostics (subsystem ae.barq.splash): per-frame progress, time-to-first-frame, main-thread hangs.
enum SplashDiag {
    static let log = Logger(subsystem: "ae.barq.splash", category: "splash")
    static let processStart = Date()   // set when the app struct initialises (first touch of this enum)
    nonisolated(unsafe) private static var watchdog: Thread?
    /// Background thread pings main every 50 ms and logs any gap > 100 ms (= main thread blocked).
    static func startHangWatch(seconds: Double = 12) {
        guard watchdog == nil else { return }
        let t = Thread {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                let sent = Date(); let sem = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { sem.signal() }
                sem.wait()
                let ms = Date().timeIntervalSince(sent) * 1000
                if ms > 100 { log.notice("HANG main blocked \(Int(ms), privacy: .public) ms at +\(Int(Date().timeIntervalSince(processStart) * 1000), privacy: .public) ms") }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        watchdog = t; t.start()
    }
}

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

// MARK: - Splash (v2: cinematic camera push through the gap between the F's arms)

/// Every launch: original FOTIQ mark (F + green dot, 1024 px original asset) holds 0.3 s, then a camera push
/// (scaleEffect anchored on the gap between the F's top and middle arms + offset bringing that gap to screen centre,
/// accelerating log-space zoom) flies through the gap; the next screen is revealed through the gap itself.
/// Reduce Motion: hold, then a plain cross-fade.
/// Frame-clamped animation clock: each rendered frame advances at most 1/30 s, so if the main thread stalls
/// (first launch builds onboarding + decodes network data underneath) the camera move resumes where it was
/// instead of jumping to t = 1. On a smooth 60 fps device this equals wall time.
final class SplashClock {
    private var last: Date?
    private(set) var elapsed: Double = 0
    func tick(_ now: Date) -> Double {
        if let l = last { elapsed += min(max(0, now.timeIntervalSince(l)), 1.0 / 30) }
        last = now
        return elapsed
    }
}

struct SplashView: View {
    var onRevealStart: () -> Void = {}
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = SplashClock()
    @State private var fade = 1.0
    /// Logo-relative unit geometry measured from design/fotiq-icon-original.png (1024x1024):
    /// white F spans x 0.28-0.67, y 0.25-0.75; top arm ends y 0.375, middle arm starts y 0.47.
    static let gap = CGRect(x: 0.415, y: 0.378, width: 0.27, height: 0.09)
    static let target = UnitPoint(x: 0.47, y: 0.423)       // camera focus: inside the gap, close to the stem
    static let hold = 0.3, push = 1.25, maxScale: CGFloat = 70
    static var held: Double? {                              // QA screenshots: -splashHold start|zoom|reveal
        switch UserDefaults.standard.string(forKey: "splashHold") { case "start": 0; case "zoom": 0.55; case "reveal": 0.86; default: nil }
    }

    /// Camera curve: accelerating ease-in (cubic) applied in log-scale space so the approach feels like real forward motion.
    static func scale(_ t: Double) -> CGFloat { exp(log(maxScale) * CGFloat(t * t * t)) }
    static func travel(_ t: Double) -> CGFloat { CGFloat(1 - pow(1 - t, 2)) * 0.6 + CGFloat(t) * 0.4 }
    /// Hole (reveal) opens during the second half, synced with the camera.
    static func hole(_ t: Double) -> CGFloat { CGFloat(max(0, min(1, (t - 0.5) / 0.35))) }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let side = W * 0.38 / 0.44                      // F + dot ≈ 38 % of screen width
            let origin = CGPoint(x: (W - side) / 2, y: (H - side) / 2)
            if reduceMotion {
                scene(t: 0, side: side, origin: origin, W: W, H: H)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 60, paused: Self.held != nil)) { tl in
                    let el = clock.tick(tl.date)
                    let _ = SplashDiag.log.notice("FRAME wall=+\(Int(tl.date.timeIntervalSince(SplashDiag.processStart) * 1000), privacy: .public)ms el=\(Int(el * 1000), privacy: .public)ms")
                    let t = Self.held ?? max(0, min(1, (el - Self.hold) / Self.push))
                    scene(t: t, side: side, origin: origin, W: W, H: H)
                }
            }
        }
        .ignoresSafeArea()
        .opacity(fade)
        .allowsHitTesting(fade > 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("splash")
        .task {
            if Self.held != nil { onRevealStart(); return }
            if reduceMotion {
                onRevealStart()
                try? await Task.sleep(for: .seconds(Self.hold + 0.2))
                withAnimation(.easeInOut(duration: 0.45)) { fade = 0 }
                try? await Task.sleep(for: .seconds(0.45))
            } else {
                // Finish on the animation's own (frame-clamped) clock, never on wall time,
                // so a main-thread stall can't cut from the first frame straight to the end.
                let deadline = Date().addingTimeInterval(10)  // safety: never block the app if frames stop
                var revealed = false
                while clock.elapsed < Self.hold + Self.push - 0.18 && Date() < deadline {
                    // mount the next screen just before the gap opens (hole starts at t = 0.5), so building it
                    // can't stall the hold or the first half of the camera push
                    if !revealed, clock.elapsed >= Self.hold + Self.push * 0.4 { revealed = true; onRevealStart() }
                    try? await Task.sleep(for: .milliseconds(16))
                }
                if !revealed { onRevealStart() }
                withAnimation(.easeOut(duration: 0.18)) { fade = 0 }
                try? await Task.sleep(for: .seconds(0.18))
            }
            onFinish()
        }
    }

    /// One frame of the camera move. Everything in logo space moves together (stem, arms, dot, navy, gap hole).
    func scene(t: Double, side: CGFloat, origin: CGPoint, W: CGFloat, H: CGFloat) -> some View {
        let s = Self.scale(t), k = Self.travel(t), h = Self.hole(t)
        let tgt = CGPoint(x: origin.x + Self.target.x * side, y: origin.y + Self.target.y * side)
        let dx = (W / 2 - tgt.x) * k, dy = (H / 2 - tgt.y) * k
        // gap hole in logo-local coords, growing from the focus point to (slightly beyond) the full gap
        let g = Self.gap, grow = 1 + max(0, h - 0.8) * 1.5
        let hw = g.width * side * h * grow, hh = g.height * side * h * grow
        let hc = CGPoint(x: Self.target.x * side, y: Self.target.y * side)
        let holeRect = CGRect(x: hc.x - hw / 2, y: hc.y - hh / 2, width: hw, height: hh)
        // Navy backdrop is drawn in SCREEN space (never scaled): scaling a vector shape 70x made SwiftUI rasterize a
        // ~100k-pt layer every frame, which froze rendering (run 41676707424: zoom frame stuck ~5 s on relaunch).
        let hcS = CGPoint(x: tgt.x + dx, y: tgt.y + dy)            // gap focus on screen (anchor + camera offset)
        let holeS = CGRect(x: hcS.x - hw * s / 2, y: hcS.y - hh * s / 2, width: hw * s, height: hh * s)
            .intersection(CGRect(x: -2, y: -2, width: W + 4, height: H + 4))
        _ = holeRect
        return ZStack(alignment: .topLeading) {
            Path { p in
                p.addRect(CGRect(x: 0, y: 0, width: W, height: H))
                if h > 0, !holeS.isNull { p.addRoundedRect(in: holeS, cornerSize: CGSize(width: min(hh * s * 0.25, 40), height: min(hh * s * 0.25, 40))) }
            }
            .fill(Color("LaunchBackground"), style: FillStyle(eoFill: true))
            Image("SplashMark").resizable().interpolation(.high).frame(width: side, height: side)
                .scaleEffect(s, anchor: Self.target)
                .offset(x: dx, y: dy)
                .position(x: origin.x + side / 2, y: origin.y + side / 2)
                .accessibilityIdentifier("splash-logo")
        }
        .frame(width: W, height: H)
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
            for l in Self.sources {
                guard let r: StandingsResponse = try? await API.shared.get("/api/standings/\(l)", maxAge: 3600) else { continue }
                let add = (r.groups.first ?? []).prefix(8).map(\.team).filter { t in !popular.contains { $0.id == t.id } }
                withAnimation(.easeOut(duration: 0.25)) { popular += add }
            }
            if popular.isEmpty { try? await Task.sleep(for: .seconds(5)) }
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
    @State private var mounted = false      // next screen is built only when the splash starts revealing it
    @State private var onboarded = Onboarding.isDone()
    var body: some View {
        ZStack {
            if mounted {
                if onboarded { content() } else { OnboardingView { withAnimation(.easeInOut(duration: 0.5)) { onboarded = true } }.transition(.opacity) }
            }
            if splash { SplashView(onRevealStart: { mounted = true }) { splash = false; mounted = true }.transition(.opacity).zIndex(1) }
        }
    }
}
