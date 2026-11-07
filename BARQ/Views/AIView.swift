import SwiftUI
import AVFoundation

struct AIView: View {
    @Environment(AppStore.self) private var store
    @State private var feed: FeedResponse?
    @State private var error: String?
    @State private var top: [Fixture] = []
    @State private var compare: Fixture?
    @State private var scorers: [TopPlayer] = []
    @State private var spin = false
    @State private var speaker = AVSpeechSynthesizer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                SectionHeader(title: "التحليل المباشر", symbol: "waveform.path.ecg")
                LoadState(value: feed, error: error, retry: load) { f in
                    if f.insights.isEmpty { EmptyState(symbol: "brain.head.profile", title: "لا توجد تحليلات حالياً", message: "التحليل يظهر فقط أثناء المباريات المباشرة وبأرقام حقيقية") }
                    ForEach(f.insights.prefix(15)) { i in
                        NavigationLink(value: Route.match(i.fixture)) { InsightCard(insight: i) }.buttonStyle(.plain)
                    }
                }
                if !top.isEmpty {
                    SectionHeader(title: "توقعات ومقارنة الفرق", symbol: "shield.lefthalf.filled")
                    Picker("المباراة", selection: $compare) {
                        ForEach(top) { Text("\($0.home.name) × \($0.away.name)").tag(Optional($0)) }
                    }.pickerStyle(.menu).buttonStyle(.glass)
                    if let c = compare { PredictionSection(fixtureId: c.id).id(c.id) }
                }
                if scorers.count >= 2 {
                    SectionHeader(title: "مقارنة اللاعبين", symbol: "person.2")
                    PlayerCompare(a: scorers[0], b: scorers[1])
                }
            }.padding(.horizontal).padding(.bottom, 30)
        }
        .screenBackground()
        .navigationTitle("FOTIQ AI")
        .barqDestinations()
        .task {
            await load()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                if scenePhase == .active { await load() }
            }
        }
        .refreshable { await load() }
    }

    var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(RadialGradient(colors: [.cyan.opacity(0.6), .purple.opacity(0.3), .clear], center: .center, startRadius: 4, endRadius: 90)).frame(width: 170, height: 170).blur(radius: 8)
                Image(systemName: "circle.hexagongrid").resizable().scaledToFit().frame(width: 140).foregroundStyle(.cyan.opacity(0.35)).rotationEffect(.degrees(spin ? 360 : 0))
                Image(systemName: "soccerball").resizable().scaledToFit().frame(width: 74).foregroundStyle(.white).shadow(color: .cyan, radius: 18)
                    .rotation3DEffect(.degrees(spin ? 360 : 0), axis: (x: 0.3, y: 1, z: 0))
            }
            .onAppear { withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { spin = true } }
            Text("محلل FOTIQ الذكي").font(.title2.bold())
            Text("يتابع \(feed?.tracking ?? 0) مباراة مباشرة الآن").font(.subheadline).foregroundStyle(.secondary)
            Button {
                let text = feed?.insights.first.map { "\($0.title). \($0.body)" } ?? L.s("لا توجد تحليلات حالياً")
                let u = AVSpeechUtterance(string: text); u.voice = AVSpeechSynthesisVoice(language: store.lang == "en" ? "en-US" : "ar-SA")
                speaker.speak(u)
            } label: { Label("اسمع آخر تحليل", systemImage: "speaker.wave.2") }
            .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
        .glassEffect(.regular.tint(.purple.opacity(0.15)), in: .rect(cornerRadius: 32))
    }

    func load() async {
        do { feed = try await API.shared.get("/api/feed"); error = nil } catch { self.error = error.localizedDescription }
        if let t: FixturesResponse = try? await API.shared.get("/api/fixtures?date=\(Fmt.day(0))", maxAge: 60) {
            top = Array(MatchSort.byImportance(t.fixtures).prefix(8)); if compare == nil { compare = top.first }
        }
        if let s: TopPlayersResponse = try? await API.shared.get("/api/topscorers/39", maxAge: 3600) { scorers = s.players }
    }
}

struct PlayerCompare: View {
    let a: TopPlayer, b: TopPlayer
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                card(a); Image(systemName: "arrow.left.arrow.right").font(.title2).foregroundStyle(.secondary); card(b)
            }
            row("الأهداف", a.goals ?? 0, b.goals ?? 0)
            row("صناعة", a.assists ?? 0, b.assists ?? 0)
            row("المباريات", a.apps ?? 0, b.apps ?? 0)
        }.padding().glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
    func card(_ p: TopPlayer) -> some View {
        NavigationLink(value: Route.player(p.id)) {
            VStack { RemoteImage(url: p.photo, fallback: "person.crop.circle", size: 64, circle: true); Text(p.name).font(.caption.bold()).lineLimit(1) }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
    }
    func row(_ t: LocalizedStringKey, _ x: Int, _ y: Int) -> some View {
        HStack { Text("\(x)").bold(x > y); Spacer(); Text(t).foregroundStyle(.secondary); Spacer(); Text("\(y)").bold(y > x) }.font(.subheadline.monospacedDigit())
    }
}
