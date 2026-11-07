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

/// Network/data work of the first screen waits until the splash is gone. Evidence (run 41687787714, splash-diag.log):
/// mounting onboarding mid-push blocked the main thread 967 + 2187 + 1237 ms (data arrival -> grid of glass tiles +
/// logo decoding), freezing the camera push. The screen is still built (empty) under the splash; only its loading waits.
/// DIAGNOSTIC ONLY (env FOTIQ_DIAG_NOGLASS=1, set only by the splash-video workflow): onboarding glass -> flat fill,
/// to measure whether first-draw of Liquid Glass causes the reveal hang. Users never get this.
extension View {
    @ViewBuilder func diagGlass<S: Shape>(_ g: Glass, in s: S) -> some View {
        if ProcessInfo.processInfo.environment["FOTIQ_DIAG_NOGLASS"] == "1" { self.background(Color.white.opacity(0.08), in: s) }
        else { self.glassEffect(g, in: s) }
    }
}

@MainActor enum LaunchGate {
    static var open = false
    static func wait() async { while !open && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(50)) } }
}

// MARK: - Persistence (pure, unit-tested)

/// First-launch flag + applying choices to the EXISTING favorites system (AppStore.favTeams / favLeagues).
enum Onboarding {
    static let doneKey = "onboardingDone"
    static let cinematicKey = "onboardingCinematicSeen"
    static let draftKey = "onboardingDraft.v1"
    struct Draft: Codable {
        var step = 0
        var clubs: [TeamRef] = []
        var leagues: Set<Int> = []
        var cups: Set<Int> = []
    }
    static func needsCinema(_ d: UserDefaults = .standard) -> Bool {
        !isDone(d) && !d.bool(forKey: cinematicKey)
    }
    static func loadDraft(_ d: UserDefaults = .standard) -> Draft {
        guard let data = d.data(forKey: draftKey), var draft = try? JSONDecoder().decode(Draft.self, from: data) else { return Draft() }
        draft.step = (0...2).contains(draft.step) ? draft.step : 0
        return draft
    }
    static func saveDraft(_ draft: Draft, _ d: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        d.set(data, forKey: draftKey)
    }
    static func isDone(_ d: UserDefaults = .standard) -> Bool {
        if ProcessInfo.processInfo.environment["FOTIQ_SKIP_ONBOARDING"] == "1" { return true }
        // CI screenshot harness (-screen / -qaFavTeam) opens screens directly; never block it with onboarding.
        if d.string(forKey: "screen") != nil || d.object(forKey: "qaFavTeam") != nil { return true }
        return d.bool(forKey: doneKey)
    }
    static func markDone(_ d: UserDefaults = .standard) { d.set(true, forKey: doneKey); d.removeObject(forKey: draftKey) }
    /// `-resetOnboarding YES` (UI tests / recording): fresh first-launch state.
    static func resetIfRequested(_ d: UserDefaults = .standard) {
        guard d.bool(forKey: "resetOnboarding") else { return }
        for k in [doneKey, cinematicKey, draftKey, "favTeams", "favLeagues", "favTeams.backup", "favLeagues.backup", PreferencesOutbox.key] { d.removeObject(forKey: k) }
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

    /// Splits saved competitions the way the picker does: missing catalog type counts as a league.
    /// Unknown ids stay with leagues so a failed catalog load cannot drop them.
    static func partition(_ ids: [Int], catalog: [LeagueMeta]) -> (leagues: Set<Int>, cups: Set<Int>) {
        let types = Dictionary(catalog.map { ($0.id, $0.type ?? "League") }, uniquingKeysWith: { a, _ in a })
        var leagues = Set<Int>(), cups = Set<Int>()
        for id in ids {
            if types[id] == "Cup" { cups.insert(id) } else { leagues.insert(id) }
        }
        return (leagues, cups)
    }

    /// Editor result: previous order kept, removals dropped, new ids appended in sorted order.
    /// An empty selection clears competitions (unlike first-launch skip, which keeps defaults).
    static func orderedEdit(previous: [Int], leagues: Set<Int>, cups: Set<Int>) -> [Int] {
        let chosen = leagues.union(cups)
        return previous.filter { chosen.contains($0) } + chosen.subtracting(previous).sorted()
    }
}

// MARK: - Cinematic portal

/// A monotonic wall-time clock. Dropped frames never lengthen the animation.
final class SplashClock {
    nonisolated(unsafe) static var nextReady = false
    nonisolated(unsafe) static var sawFirstFrame = false
    private var loggedFirstVisualFrame = false
    private var start: TimeInterval?
    private var previous: TimeInterval?
    private(set) var largestFrameGap: Double = 0
    private(set) var elapsed: Double = 0
    func tick(_ now: TimeInterval = ProcessInfo.processInfo.systemUptime, active: Bool = true) -> Double {
        if !loggedFirstVisualFrame {
            loggedFirstVisualFrame = true
            Self.sawFirstFrame = true
            SplashDiag.log.notice("FIRST splash frame +\(Int(Date().timeIntervalSince(SplashDiag.processStart) * 1000), privacy: .public)ms")
        }
        // Keep the original F perfectly still while SwiftUI compiles and commits the
        // destination's first frame. Starting the camera clock before that commit used
        // to consume most of the 1.75 s transition inside a main-thread layout stall,
        // which looked like a normal cut instead of a fly-through.
        guard active else {
            start = nil
            previous = nil
            largestFrameGap = 0
            elapsed = 0
            return 0
        }
        if start == nil {
            start = now
            previous = now
            SplashDiag.log.notice("START camera +\(Int(Date().timeIntervalSince(SplashDiag.processStart) * 1000), privacy: .public)ms")
        }
        if let previous { largestFrameGap = max(largestFrameGap, now - previous) }
        previous = now
        elapsed = max(0, now - (start ?? now))
        return elapsed
    }
}

struct SplashView: View {
    var cinematic = true
    var onRevealStart: () -> Void = {}
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = SplashClock()
    @State private var fade = 1.0
    // Measured from the existing 1024px asset: clear space x414..622, y377..471.
    // The aperture stays INSIDE that space, never erasing part of the white F.
    static let gap = CGRect(x: 0.410, y: 0.372, width: 0.190, height: 0.084)
    static let target = UnitPoint(x: gap.midX, y: gap.midY)
    static let visibleWidth: CGFloat = 0.24
    static let hold = 0.30, push = 1.45, maxScale: CGFloat = 60
    static var held: Double? {
        switch UserDefaults.standard.string(forKey: "splashHold") {
        case "start": 0; case "zoom": 0.55; case "reveal": 0.86; default: nil
        }
    }
    static func ease(_ t: Double) -> Double { let x = min(1, max(0, t)); return x * x * x * (x * (x * 6 - 15) + 10) }
    /// Pinhole projection: moving the camera toward the logo plane changes its apparent size.
    static func scale(_ t: Double) -> CGFloat {
        let distance = exp(-log(Double(maxScale)) * ease(t))
        return CGFloat(1 / distance)
    }
    static func travel(_ t: Double) -> CGFloat { CGFloat(ease(min(1, t / 0.8))) }
    static func hole(_ t: Double) -> CGFloat { CGFloat(ease(t / 0.28)) }
    static func aperture(t: Double, size: CGSize) -> CGRect {
        let side = size.width * Self.visibleWidth / 0.442
        let focus = CGPoint(x: (size.width - side) / 2 + target.x * side,
                            y: (size.height - side) / 2 + target.y * side)
        let k = travel(t), scale = scale(t), open = hole(t)
        let center = CGPoint(x: focus.x + (size.width / 2 - focus.x) * k,
                             y: focus.y + (size.height / 2 - focus.y) * k)
        let width = gap.width * side * scale * open, height = gap.height * side * scale * open
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }
    var body: some View {
        TimelineView(.animation(paused: Self.held != nil)) { _ in
            let elapsed = clock.tick(active: SplashClock.nextReady)
            let t = Self.held ?? (cinematic && !reduceMotion ? min(1, max(0, (elapsed - Self.hold) / Self.push)) : 0)
            Canvas(rendersAsynchronously: true) { context, size in
                let bounds = CGRect(origin: .zero, size: size)
                if t > 0 && Self.aperture(t: t, size: size).contains(bounds) { return }
                var cover = Path(bounds)
                if t > 0 { cover.addRect(Self.aperture(t: t, size: size)) }
                // Clip BOTH the navy and original bitmap. The old bitmap's opaque navy
                // otherwise hid the destination even when the backdrop had a hole.
                context.clip(to: cover, style: FillStyle(eoFill: true))
                context.fill(Path(bounds), with: .color(Color("LaunchBackground").opacity(0.995)))
                let side = size.width * Self.visibleWidth / 0.442
                let s = Self.scale(t), k = Self.travel(t)
                let focus = CGPoint(x: (size.width - side) / 2 + Self.target.x * side,
                                    y: (size.height - side) / 2 + Self.target.y * side)
                let center = CGPoint(x: focus.x + (size.width / 2 - focus.x) * k,
                                     y: focus.y + (size.height / 2 - focus.y) * k)
                let rect = CGRect(x: center.x - Self.target.x * side * s,
                                  y: center.y - Self.target.y * side * s, width: side * s, height: side * s)
                context.draw(context.resolve(Image("SplashMark")), in: rect)
            }
        }
        .ignoresSafeArea().opacity(fade)
        .accessibilityElement(children: .ignore).accessibilityIdentifier("splash")
        .task {
            guard Self.held == nil else { onRevealStart(); return }
            let duration = cinematic && !reduceMotion ? Self.hold + Self.push : 0.40
            while clock.elapsed < duration && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(8))
            }
            guard !Task.isCancelled else { return }
            onRevealStart()
            if !cinematic || reduceMotion {
                withAnimation(.easeOut(duration: 0.20)) { fade = 0 }
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
            // Cinematic removal has NO opacity transition: the aperture already covers
            // the viewport. Its last rendered frame and the uncovered page are identical.
            SplashDiag.log.notice("FINISH cinematic=\(cinematic, privacy: .public) elapsed=\(clock.elapsed, privacy: .public) ready=\(SplashClock.nextReady, privacy: .public) maxFrameGap=\(clock.largestFrameGap, privacy: .public)")
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
    /// Editing must not show league/cup ticks until ids are split by catalog type.
    /// Copying every favorite into both sets made unchecking a league a no-op (the cup set still held it).
    @State private var compsReady = false

    init(editing: Bool = false, onDone: @escaping () -> Void) {
        self.editing = editing
        self.onDone = onDone
        let draft = editing ? Onboarding.Draft() : Onboarding.loadDraft()
        _step = State(initialValue: draft.step)
        _clubs = State(initialValue: draft.clubs)
        _leagues = State(initialValue: draft.leagues)
        _cups = State(initialValue: draft.cups)
    }

    private func persistDraft() {
        guard !editing, !Onboarding.isDone() else { return }
        Onboarding.saveDraft(.init(step: step, clubs: clubs, leagues: leagues, cups: cups))
    }

    var body: some View {
        VStack(spacing: 0) {
            header.onAppear { SplashDiag.log.notice("ONB appear +\(Int(Date().timeIntervalSince(SplashDiag.processStart) * 1000), privacy: .public)ms") }
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
        .onChange(of: step) { persistDraft() }
        .onChange(of: clubs) { persistDraft() }
        .onChange(of: leagues) { persistDraft() }
        .onChange(of: cups) { persistDraft() }
        .onAppear {
            guard editing else { return }
            clubs = store.favTeams
        }
        .task {
            guard editing, !compsReady else { return }
            let catalog = (try? await API.shared.get("/api/catalog", maxAge: 3600, attempts: 1) as CatalogResponse)?.leagues ?? []
            let parts = Onboarding.partition(store.favLeagues, catalog: catalog)
            leagues = parts.leagues
            cups = parts.cups
            compsReady = true
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
                    .padding(.horizontal, 12).padding(.vertical, 6).diagGlass(.regular, in: .capsule)
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
            Group {
                Button { advance() } label: { Text("تخطي").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass).controlSize(.large).disabled(editing && !compsReady).accessibilityIdentifier("ob-skip")
            }
            Button { advance() } label: {
                Label(step == 2 ? "ابدأ الآن" : "التالي", systemImage: step == 2 ? "checkmark" : "chevron.forward")
                    .labelStyle(.titleAndIcon).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(Color("BrandGreen")).controlSize(.large)
            .disabled((editing && !compsReady) || (step == 0 && clubs.isEmpty))
            .accessibilityIdentifier(step == 2 ? "ob-start" : "ob-next")
        }
        .environment(\.layoutDirection, .leftToRight)
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
            store.favLeagues = Onboarding.orderedEdit(previous: store.favLeagues, leagues: leagues, cups: cups)
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
    @State private var model = ClubPickerModel()
    @State private var directoryReady = true
    @State private var q = ""
    @State private var popularRetry = 0
    @State private var searchRetry = 0
    let cols = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var shown: [TeamRef] {
        guard directoryReady else { return [] }
        let base = q.trimmingCharacters(in: .whitespaces).count >= 2 ? model.results : model.popular
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
            .padding(12).diagGlass(.regular, in: .capsule).padding(.horizontal)
            ScrollView {
                if let message = q.trimmingCharacters(in: .whitespaces).count >= 2 ? model.searchError : model.error {
                    VStack(spacing: 8) {
                        Text(message).font(.footnote).multilineTextAlignment(.center)
                        Button("إعادة المحاولة") {
                            if q.trimmingCharacters(in: .whitespaces).count >= 2 { searchRetry += 1 } else { popularRetry += 1 }
                        }.buttonStyle(.glass).accessibilityIdentifier("ob-retry")
                    }.padding()
                }
                if shown.isEmpty {
                    if model.searching || !directoryReady {
                        ProgressView().padding(.top, 60).accessibilityIdentifier("ob-loading")
                    } else if model.searchError == nil {
                        Text("ما لقينا نتائج").foregroundStyle(.secondary).padding(.top, 40)
                    }
                }
                // One GlassEffectContainer for the grid: Apple's API to let many glass shapes share rendering passes.
                GlassEffectContainer(spacing: 12) {
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(shown) { t in
                            PickTile(id: "ob-club-\(t.id)", name: t.name, logo: t.logo, on: selected.contains { $0.id == t.id }) {
                                if let i = selected.firstIndex(where: { $0.id == t.id }) { selected.remove(at: i) } else { selected.append(t) }
                            }
                            .equatable()
                        }
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .task(id: popularRetry) {
            await LaunchGate.wait()
            guard !Task.isCancelled else { return }
            directoryReady = true
            await model.loadPopular()
        }
        .task(id: "\(q)|\(searchRetry)") {
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            await model.search(q)
        }
    }

}

/// Real leagues ("League") or cups/international competitions ("Cup") from the backend catalog.
struct CompetitionPickStep: View {
    let kind: String
    @Binding var selected: Set<Int>
    @State private var items: [LeagueMeta] = []
    @State private var q = ""
    @State private var loading = true
    @State private var error: String?
    @State private var retry = 0
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
            .padding(12).diagGlass(.regular, in: .capsule).padding(.horizontal)
            ScrollView {
                if loading && items.isEmpty { ProgressView().padding(.top, 60).accessibilityIdentifier("ob-loading") }
                if let error {
                    VStack(spacing: 8) {
                        Text(error).font(.footnote).multilineTextAlignment(.center)
                        Button("إعادة المحاولة") { retry += 1 }.buttonStyle(.glass).accessibilityIdentifier("ob-retry")
                    }.padding()
                } else if !loading && shown.isEmpty {
                    Text("ما لقينا نتائج").foregroundStyle(.secondary).padding()
                }
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
        .task(id: "\(kind)|\(retry)") {
            await LaunchGate.wait()
            guard !Task.isCancelled else { return }
            loading = true; error = nil
            defer { loading = false }
            do {
                let c: CatalogResponse = try await API.shared.get("/api/catalog", maxAge: 3600, attempts: 1)
                guard !Task.isCancelled else { return }
                items = CompetitionOrder.sorted(c.leagues, kind: kind)
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }

}

struct PickTile: View, Equatable {
    static func == (a: PickTile, b: PickTile) -> Bool { a.id == b.id && a.on == b.on && a.name == b.name && a.logo == b.logo }
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
            .diagGlass(on ? .regular.tint(Color("BrandGreen").opacity(0.25)) : .regular, in: .rect(cornerRadius: 18))
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
    @State private var cinematic = Onboarding.needsCinema()
    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            // Build and lay out the destination before the first animated splash frame.
            // iOS keeps the matching static launch screen visible while this initial work
            // completes, and LaunchGate still prevents network work until the reveal ends.
            Group {
                if onboarded { content() } else { OnboardingView { withAnimation(.easeInOut(duration: 0.5)) { onboarded = true } }.transition(.opacity) }
            }
            .onAppear {
                SplashDiag.log.notice("NEXT page appear +\(Int(Date().timeIntervalSince(SplashDiag.processStart) * 1000), privacy: .public)ms")
                // next runloop turn = after its first layout/draw commit
                DispatchQueue.main.async {
                    SplashDiag.log.notice("NEXT page drawn +\(Int(Date().timeIntervalSince(SplashDiag.processStart) * 1000), privacy: .public)ms")
                    SplashClock.nextReady = true
                }
            }
            if splash {
                SplashView(cinematic: cinematic, onRevealStart: {}) {
                    UserDefaults.standard.set(true, forKey: Onboarding.cinematicKey)
                    splash = false
                    // Yield a frame so the uncovered interface appears before starting data work.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(50))
                        LaunchGate.open = true
                    }
                }.zIndex(1)
            }
        }
    }
}
