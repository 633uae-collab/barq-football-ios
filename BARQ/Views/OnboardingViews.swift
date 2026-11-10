import SwiftUI
import os
import UIKit

/// Splash diagnostics (subsystem ae.barq.splash): per-frame progress, time-to-first-frame, main-thread hangs.
enum SplashDiag {
    static let log = Logger(subsystem: "ae.barq.splash", category: "splash")
    static let points = OSLog(subsystem: "ae.barq.splash", category: .pointsOfInterest)
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
/// logo decoding), blocking the launch transition. The screen is still built (empty) under the splash; only its loading waits.
/// DIAGNOSTIC ONLY (env FOTIQ_DIAG_NOGLASS=1, set only by the splash-video workflow): onboarding glass -> flat fill,
/// to measure whether first-draw of Liquid Glass causes the reveal hang. Users never get this.
extension View {
    @ViewBuilder func diagGlass<S: Shape>(_ g: Glass, in s: S) -> some View {
        if ProcessInfo.processInfo.environment["FOTIQ_DIAG_NOGLASS"] == "1" { self.background(Color.white.opacity(0.08), in: s) }
        else { self.glassEffect(g, in: s) }
    }
}

@MainActor enum LaunchGate {
    private static var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    static var open = false {
        didSet {
            guard open else { return }
            let pending = Array(waiters.values)
            waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
    }
    static func wait() async {
        guard !open, !Task.isCancelled else { return }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if open || Task.isCancelled { continuation.resume() }
                else { waiters[id] = continuation }
            }
        } onCancel: {
            Task { @MainActor in waiters.removeValue(forKey: id)?.resume() }
        }
    }
}

// MARK: - Persistence (pure, unit-tested)

/// First-launch flag + applying choices to the EXISTING favorites system (AppStore.favTeams / favLeagues).
enum Onboarding {
    static let doneKey = "onboardingDone"
    static let draftKey = "onboardingDraft.v1"
    struct Draft: Codable {
        var step = 0
        var clubs: [TeamRef] = []
        var leagues: Set<Int> = []
        var cups: Set<Int> = []
    }
    static func loadDraft(_ d: UserDefaults = .standard) -> Draft {
        guard let data = d.data(forKey: draftKey), var draft = try? JSONDecoder().decode(Draft.self, from: data) else { return Draft() }
        draft.step = !draft.clubs.isEmpty && (0...2).contains(draft.step) ? draft.step : 0
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
        for k in [doneKey, "onboardingCinematicSeen", draftKey, "favTeams", "favLeagues", "favTeams.backup", "favLeagues.backup", PreferencesOutbox.key] { d.removeObject(forKey: k) }
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

// MARK: - Launch timing and accessible fallback

/// A monotonic wall-time clock. Dropped frames never lengthen the animation.
final class SplashClock {
    nonisolated(unsafe) static var nextReady = false
    nonisolated(unsafe) static var sawFirstFrame = false
    var onFirstFrame: (() -> Void)?
    private var loggedFirstVisualFrame = false
    private var firstVisualTime: TimeInterval?
    private(set) var timelineOffset: Double = 0
    var activeDuration: Double { max(0, elapsed - timelineOffset) }
    func displayedFor(at now: TimeInterval) -> Double { max(0, now - (firstVisualTime ?? now)) }
    func begin(at now: TimeInterval, timelineOffset: Double) {
        self.timelineOffset = timelineOffset
        start = now; previous = now
        SplashDiag.log.notice("START launch +\(Int(Date().timeIntervalSince(SplashDiag.processStart) * 1000), privacy: .public)ms timelineOffset=\(timelineOffset, privacy: .public) uptime=\(now, privacy: .public)")
        os_signpost(.begin, log: SplashDiag.points, name: "Rider motion")
    }
    private var start: TimeInterval?
    private var previous: TimeInterval?
    private var startupPrevious: TimeInterval?
    private(set) var startupLargestFrameGap: Double = 0
    private var frameGaps: [Double] = []
    var sampledFrames: Int { frameGaps.count }
    var meanFrameGap: Double { frameGaps.isEmpty ? 0 : frameGaps.reduce(0, +) / Double(frameGaps.count) }
    var percentile95Gap: Double {
        let sorted = frameGaps.sorted()
        return sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))]
    }
    private(set) var largestFrameGap: Double = 0
    private(set) var elapsed: Double = 0
    var animationCompleted = false
    func tick(_ now: TimeInterval = CACurrentMediaTime(), active: Bool = true) -> Double {
        if let startupPrevious, now > startupPrevious {
            startupLargestFrameGap = max(startupLargestFrameGap, now - startupPrevious)
        }
        startupPrevious = now
        if !loggedFirstVisualFrame {
            loggedFirstVisualFrame = true
            firstVisualTime = now
            Self.sawFirstFrame = true
            let callback = onFirstFrame
            onFirstFrame = nil
            callback?()
            SplashDiag.log.notice("FIRST splash frame +\(Int(Date().timeIntervalSince(SplashDiag.processStart) * 1000), privacy: .public)ms")
        }
        // Prewarm the destination before the fixed hold-and-fade timeline starts.
        guard active else {
            start = nil
            previous = nil
            largestFrameGap = 0
            frameGaps.removeAll(keepingCapacity: true)
            elapsed = 0
            return 0
        }
        if start == nil {
            start = now
            previous = now
            SplashDiag.log.notice("START launch +\(Int(Date().timeIntervalSince(SplashDiag.processStart) * 1000), privacy: .public)ms")
        }
        if let previous, now > previous {
            let gap = now - previous
            if gap > 1.0 / 30 {
                SplashDiag.log.notice("FRAME_GAP seconds=\(gap, privacy: .public) fromUptime=\(previous, privacy: .public) toUptime=\(now, privacy: .public)")
                os_signpost(.event, log: SplashDiag.points, name: "Rider callback gap", "gap=%.6f from=%.6f to=%.6f", gap, previous, now)
            }
            largestFrameGap = max(largestFrameGap, gap)
            if frameGaps.count < 512 { frameGaps.append(gap) }
        }
        previous = now
        elapsed = timelineOffset + max(0, now - (start ?? now))
        return elapsed
    }
}

/// Fixed original mark and opacity-only fallback for Reduce Motion.
enum LaunchPresentation {
    // Attached 1320x2868 screenshot: visible artwork y=1322..<1546 (224 px).
    // Size comes from that measurement; the crop includes one AA pixel per edge.
    static let referenceScreenWidth: CGFloat = 1320
    static let referenceMarkHeight: CGFloat = 224
    static let hold = 0.5, fade = 0.3
    static let duration = hold + fade
    static func opacity(at elapsed: Double) -> Double {
        let t = min(1, max(0, (elapsed - hold) / fade))
        return 1 - t * t * (3 - 2 * t)
    }
    static func logoRect(in size: CGSize) -> CGRect {
        let scale = size.width / referenceScreenWidth * referenceMarkHeight / 512
        let width = 455 * scale, height = 514 * scale
        return CGRect(x: (size.width-width)/2, y: (size.height-height)/2, width: width, height: height)
    }
}

struct SplashView: View {
    var firstLaunch: Bool
    var onFinish: () -> Void
    @State private var clock = SplashClock()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        PremiumLaunchSurface(clock: clock, reduceMotion: reduceMotion) {
                os_signpost(.end, log: SplashDiag.points, name: "Rider motion")
                SplashDiag.log.notice("FINISH firstLaunch=\(firstLaunch, privacy: .public) elapsed=\(clock.elapsed, privacy: .public) ready=\(SplashClock.nextReady, privacy: .public) maxFrameGap=\(clock.largestFrameGap, privacy: .public) mode=\(reduceMotion ? "reduced" : "premium", privacy: .public)")
                SplashDiag.log.notice("MOTION committedToCompletion=\(clock.activeDuration, privacy: .public) creditedStaticHold=\(clock.timelineOffset, privacy: .public) finishEpoch=\(Date().timeIntervalSince1970, privacy: .public)")
                SplashDiag.log.notice("STARTUP appInitToFinish=\(Date().timeIntervalSince(SplashDiag.processStart), privacy: .public) maxCallbackGapIncludingPreparation=\(clock.startupLargestFrameGap, privacy: .public)")
                SplashDiag.log.notice("FRAME_STATS samples=\(clock.sampledFrames, privacy: .public) mean=\(clock.meanFrameGap, privacy: .public) p95=\(clock.percentile95Gap, privacy: .public)")
                onFinish()
            }
            .ignoresSafeArea()
            .accessibilityElement(children: .ignore).accessibilityIdentifier("splash")
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
                    .buttonStyle(.glass).controlSize(.large).disabled((editing && !compsReady) || (!editing && step == 0)).accessibilityIdentifier("ob-skip")
            }
            Button { advance() } label: {
                HStack(spacing: 8) {
                    Image(systemName: step == 2 ? "checkmark" : "chevron.left")
                    Text(step == 2 ? "ابدأ الآن" : "التالي")
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(Color("BrandGreen")).controlSize(.large)
            .disabled((editing && !compsReady) || (step == 0 && clubs.isEmpty))
            .accessibilityIdentifier(step == 2 ? "ob-start" : "ob-next")
        }
        .environment(\.layoutDirection, .leftToRight)
        .padding()
    }

    func advance() {
        guard editing || !clubs.isEmpty else { return }
        if step < 2 { withAnimation(.snappy) { step += 1 }; return }
        finish()
    }
    func finish() {
        guard editing || !clubs.isEmpty else { return }
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
        .task {
            await ImageStore.shared.preload(model.popular.compactMap(\.logo))
        }
        .task(id: popularRetry) {
            await LaunchGate.wait()
            guard !Task.isCancelled else { return }
            directoryReady = true
            await model.loadPopular()
            await ImageStore.shared.preload(model.popular.compactMap(\.logo))
        }
        .task(id: "\(q)|\(searchRetry)") {
            await LaunchGate.wait()
            guard !Task.isCancelled else { return }
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

/// One native launch container per scene lifetime; returning from the background
/// retains the destination and cannot recreate the entrance.
struct LaunchFlow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @State private var onboarded = Onboarding.isDone()
    @State private var firstLaunch = !Onboarding.isDone()
    var body: some View {
        LaunchContainer(firstLaunch: firstLaunch,
                        revision: "\(onboarded)|\(store.lang)|\(colorScheme)",
                        prepare: prepareDestination) {
            if onboarded { content() }
            else {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.5)) { onboarded = true }
                }.transition(.opacity)
            }
        }
        .ignoresSafeArea()
    }
    @MainActor private func prepareDestination() async {
        if onboarded {
            LaunchHomePreparation.snapshot = await LaunchHomeCache.shared.restore(scope: LaunchHomePreparation.scope)
            if let snapshot = LaunchHomePreparation.snapshot {
                let favorites = HomeFeed.Favorites(matches: Set(store.savedMatches),
                    teams: Set(store.favTeams.map(\.id)), leagues: Set(store.favLeagues))
                let addresses = snapshot.visibleImageAddresses(favorites: favorites, now: Date())
                LaunchHomePreparation.images = await LaunchHomeCache.shared.prepareCachedImages(addresses)
            }
            SplashDiag.log.notice("HOME preparedLocalSnapshot=\(LaunchHomePreparation.snapshot != nil, privacy: .public)")
        } else {
            // Reusing locally cached club logos must not enqueue one SwiftUI
            // state publication per image in the middle of erasure.
            let draft = Onboarding.loadDraft()
            let clubs = draft.clubs + ClubDirectory.initial(.standard)
            let addresses = Array(Set(clubs.compactMap(\.logo)))
            LaunchHomePreparation.images = await LaunchHomeCache.shared.prepareCachedImages(addresses)
        }
    }
}
