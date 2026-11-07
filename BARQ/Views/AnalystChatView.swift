import SwiftUI

struct AnalystChatView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var welcome: AnalystWelcome?
    @State private var visible = false
    @State private var archive = AnalystConversations()
    @State private var question = ""
    @State private var sending = false
    @State private var showingHistory = false
    @FocusState private var writing: Bool
    private var en: Bool { L.lang == "en" }
    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if archive.current.turns.isEmpty {
                        VStack(spacing: 16) {
                            BrandMark(height: 48).accessibilityIdentifier("analyst-welcome-logo")
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                Text(welcome?.displayText(at: timeline.date, english: en) ?? AnalystWelcome.fallback(english: en))
                                    .font(.title3.weight(.medium)).multilineTextAlignment(.center).accessibilityIdentifier("analyst-welcome")
                            }
                        }.frame(maxWidth: .infinity).padding(.vertical, 50)
                    }
                    ForEach(archive.current.turns) { message in
                        VStack(alignment: .leading, spacing: 16) {
                            HStack { Spacer(minLength: 28)
                                Text(message.question).textSelection(.enabled).padding(14)
                                    .glassEffect(.regular.tint(.green.opacity(0.08)), in: .rect(cornerRadius: 20))
                            }
                            if let reply = message.answer {
                                Text((try? AttributedString(markdown: reply.answer, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(reply.answer))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .environment(\.layoutDirection, reply.answer.range(of: "[\\u0600-\\u06FF]", options: .regularExpression) == nil ? .leftToRight : .rightToLeft)
                                    .textSelection(.enabled).accessibilityIdentifier(message.id == archive.current.turns.last?.id ? "analyst-answer" : "analyst-previous-answer")
                                    .contextMenu { Button(en ? "Copy" : "نسخ", systemImage: "doc.on.doc") { UIPasteboard.general.string = reply.answer } }
                                Text("API-Football · " + (en ? "Data retrieved: " : "وقت جلب البيانات: ") + Date(timeIntervalSince1970: reply.fetchedAt / 1000).formatted(date: .abbreviated, time: .standard))
                                    .font(.caption2).foregroundStyle(.secondary)
                            } else if let error = message.error {
                                Text(error).foregroundStyle(.red).accessibilityIdentifier(message.id == archive.current.turns.last?.id ? "analyst-error" : "analyst-previous-error")
                            } else if sending {
                                ProgressView(en ? "Fetching data and analyzing…" : "نجلب البيانات ونجهز الإجابة…").accessibilityIdentifier("analyst-loading")
                            } else {
                                Text(en ? "This request was interrupted. Send a new question to continue." : "انقطع هذا الطلب. أرسل سؤالك مجدداً للمتابعة.").foregroundStyle(.secondary)
                            }
                        }.id(message.id)
                    }
                    Color.clear.frame(height: 1).id("chat-bottom")
                }.padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { scroll.scrollTo("chat-bottom", anchor: .bottom) }
            .onChange(of: archive.current.turns.count) { _, _ in withAnimation { scroll.scrollTo("chat-bottom", anchor: .bottom) } }
            .onChange(of: sending) { _, value in if !value { withAnimation { scroll.scrollTo("chat-bottom", anchor: .bottom) } } }
            .onChange(of: archive.selectedID) { _, _ in scroll.scrollTo("chat-bottom", anchor: .bottom) }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .task(id: "\(visible)-\(scenePhase == .active)-\(archive.current.turns.isEmpty)-\(en)") {
            guard visible, scenePhase == .active, archive.current.turns.isEmpty else { return }
            welcome = nil
            while !Task.isCancelled {
                if let value = try? await API.shared.analystWelcome(language: en ? "en" : "ar"), !Task.isCancelled { welcome = value }
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(en ? "Conversations" : "المحادثات", systemImage: "clock.arrow.circlepath") { showingHistory = true }
                    .accessibilityIdentifier("analyst-history").disabled(sending)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(en ? "New conversation" : "محادثة جديدة", systemImage: "square.and.pencil") { newConversation() }
                    .accessibilityIdentifier("analyst-new-chat").disabled(sending)
            }
        }
        .sheet(isPresented: $showingHistory) {
            NavigationStack {
                List {
                    Button(en ? "New conversation" : "محادثة جديدة") { newConversation(); showingHistory = false }
                    ForEach(archive.conversations.filter { !$0.turns.isEmpty }) { conversation in
                        Button { archive.selectedID = conversation.id; showingHistory = false } label: {
                            VStack(alignment: .leading) {
                                Text(conversation.title).lineLimit(2)
                                Text(conversation.createdAt.formatted()).font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("analyst-saved-conversation")
                    }
                    NavigationLink(en ? "Live insights & comparisons" : "التحليل المباشر والمقارنات") { AnalystInsightsView() }
                }.navigationTitle(en ? "Conversations" : "المحادثات")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(en ? "Done" : "تم") { showingHistory = false } } }
            }
        }
    }
    private var composer: some View {
        VStack(spacing: 10) {
            if let error = archive.storageError { Text(error).font(.caption).foregroundStyle(.red) }
            HStack(alignment: .bottom, spacing: 12) {
                TextField(en ? "Ask about football…" : "اكتب سؤالك عن كرة القدم…", text: $question, axis: .vertical)
                    .lineLimit(1...5).focused($writing).accessibilityIdentifier("analyst-question")
                    .onChange(of: question) { _, value in if value.count > 1000 { question = String(value.prefix(1000)) } }
                Button { Task { await send() } } label: { Image(systemName: "arrow.up").font(.headline).frame(width: 28, height: 28) }
                    .buttonStyle(.glassProminent).accessibilityLabel(en ? "Send" : "إرسال")
                    .disabled(sending || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("analyst-send")
            }.padding(12).glassEffect(.regular, in: .rect(cornerRadius: 25))
        }.padding(.horizontal).padding(.vertical, 8)
    }
    private func newConversation() {
        archive.newConversation(); question = ""
    }
    @MainActor private func send() async {
        guard !sending else { return }
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let conversationID = archive.selectedID else { return }
        let history = archive.current.history
        let context = archive.current.context
        writing = false; sending = true; question = ""
        let message = AnalystTurn(question: text)
        archive.append(message, context: context)
        defer { sending = false }
        do {
            let reply = try await API.shared.askAnalyst(text, context: context, history: history)
            archive.finish(conversation: conversationID, turn: message.id, reply: reply)
        } catch {
            let messageText: String
            if let network = error as? URLError, [.secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate].contains(network.code) {
                messageText = en ? "A secure connection could not be established. Please try again. Your message is saved; no automatic resend was made." : "تعذّر إنشاء اتصال آمن. حاول مجدداً. سؤالك محفوظ ولم نُعد إرساله تلقائياً."
            } else { messageText = error.localizedDescription }
            archive.finish(conversation: conversationID, turn: message.id, error: messageText)
        }
    }
}
