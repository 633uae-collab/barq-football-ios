import SwiftUI

struct AnalystChatView: View {
    struct Message: Identifiable {
        let id = UUID()
        let question: String
        var answer: AnalystReply?
        var error: String?
    }
    @State private var question = ""
    @State private var messages: [Message] = []
    @State private var sending = false
    @State private var search = ""
    @State private var results: SearchResponse?
    @State private var selectedPlayers: [SearchResponse.P] = []
    @State private var selectedTeams: [SearchResponse.T] = []
    @State private var searchError: String?
    @FocusState private var writing: Bool
    private var en: Bool { L.lang == "en" }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrandHeading(symbol: "bubble.left.and.bubble.right", title: en ? "Ask" : "اسأل")
            DisclosureGroup {
                TextField(en ? "Search by name" : "ابحث بالاسم", text: $search)
                    .accessibilityIdentifier("analyst-entity-search").textFieldStyle(.roundedBorder).onSubmit { Task { await find() } }
                Button(en ? "Search" : "بحث") { Task { await find() } }.buttonStyle(.glass).accessibilityIdentifier("analyst-entity-find")
                if let searchError { Text(searchError).font(.caption).foregroundStyle(.red) }
                ForEach(results?.teams.prefix(5) ?? []) { team in
                    Button(team.name) { if !selectedTeams.contains(team) && selectedTeams.count < 2 { selectedTeams.append(team) }; results = nil }
                }
                ForEach(results?.players.prefix(5) ?? []) { player in
                    Button(player.name) { if !selectedPlayers.contains(player) && selectedPlayers.count < 2 { selectedPlayers.append(player) }; results = nil }.accessibilityIdentifier("analyst-player-\(player.id)")
                }
            } label: {
                Text(en ? "Select teams or players (optional)" : "اختيار أندية أو لاعبين (اختياري)")
                    .accessibilityIdentifier("analyst-entity-picker")
            }
            ForEach(selectedTeams) { team in
                Button { selectedTeams.removeAll { $0.id == team.id } } label: { Label(team.name, systemImage: "xmark.circle") }
            }
            ForEach(selectedPlayers) { player in
                Button { selectedPlayers.removeAll { $0.id == player.id } } label: { Label(player.name, systemImage: "xmark.circle") }
            }
            ForEach(messages) { message in
                VStack(alignment: .leading, spacing: 8) {
                    Text(message.question).font(.subheadline.bold()).textSelection(.enabled)
                    if let reply = message.answer {
                        Text(reply.answer).textSelection(.enabled).accessibilityIdentifier("analyst-answer")
                        Text("API-Football · " + (en ? "Data retrieved: " : "وقت جلب البيانات: ") + Date(timeIntervalSince1970: reply.fetchedAt / 1000).formatted(date: .abbreviated, time: .standard))
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(reply.model).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let error = message.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("analyst-error") }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }
            if sending { ProgressView(en ? "Fetching match data and analyzing…" : "نجلب بيانات المباراة ونحلّلها…").accessibilityIdentifier("analyst-loading") }
            TextField(en ? "Ask about football…" : "اكتب سؤالك عن كرة القدم…", text: $question, axis: .vertical)
                .lineLimit(2...5).focused($writing).accessibilityIdentifier("analyst-question")
                .onChange(of: question) { _, value in if value.count > 1000 { question = String(value.prefix(1000)) } }
            Button { Task { await send() } } label: { Label(en ? "Send" : "إرسال", systemImage: "arrow.up.circle.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.glassProminent).disabled(sending || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("analyst-send")
        }.padding().glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
    @MainActor private func find() async {
        guard search.count >= 3 else { return }
        do {
            let query = search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            results = try await API.shared.get("/api/search?q=\(query)", attempts: 1)
            searchError = nil
        } catch { searchError = error.localizedDescription }
    }
    @MainActor private func send() async {
        guard !sending else { return }
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        writing = false; sending = true; question = ""
        let message = Message(question: text)
        messages.append(message)
        defer { sending = false }
        do {
            let context = AnalystContext(teamIds: selectedTeams.isEmpty ? nil : selectedTeams.map(\.id), playerIds: selectedPlayers.isEmpty ? nil : selectedPlayers.map(\.id))
            let reply = try await API.shared.askAnalyst(text, context: context)
            if let index = messages.firstIndex(where: { $0.id == message.id }) { messages[index].answer = reply }
        } catch {
            if let index = messages.firstIndex(where: { $0.id == message.id }) { messages[index].error = error.localizedDescription }
        }
    }
}
