import SwiftUI
import OSLog

struct AnalystChatView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var welcome: AnalystWelcome?
    @State private var visible = false
    @State private var archive = AnalystConversations()
    @State private var question = ""
    @State private var sending = false
    @State private var showingHistory = false
    @FocusState private var writing: Bool
    private let composerLog = Logger(subsystem: "ae.barq.composer", category: "interaction")
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
                                Text(verbatim: message.question).textSelection(.enabled).padding(14)
                                    .glassEffect(.regular.tint(.green.opacity(0.08)), in: .rect(cornerRadius: 20))
                            }
                            if let reply = message.answer {
                                let renderedAnswer = (try? AttributedString(markdown: reply.answer, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(reply.answer)
                                Text(renderedAnswer)
                                    // Give VoiceOver/XCTest the already resolved text. Do not ask
                                    // SwiftUI to localize server Markdown while taking a snapshot.
                                    .accessibilityLabel(Text(verbatim: String(renderedAnswer.characters)))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .environment(\.layoutDirection, reply.answer.range(of: "[\\u0600-\\u06FF]", options: .regularExpression) == nil ? .leftToRight : .rightToLeft)
                                    .textSelection(.enabled).accessibilityIdentifier(message.id == archive.current.turns.last?.id ? "analyst-answer" : "analyst-previous-answer")
                                    .contextMenu { Button(en ? "Copy" : "نسخ", systemImage: "doc.on.doc") { UIPasteboard.general.string = reply.answer } }
                                Text((reply.sourceNames ?? (en ? "Source details unavailable" : "تفاصيل المصدر غير متوفرة")) + " · " + (en ? "Data retrieved: " : "وقت جلب البيانات: ") + Date(timeIntervalSince1970: reply.fetchedAt / 1000).formatted(date: .abbreviated, time: .standard))
                                    .font(.caption2).foregroundStyle(.secondary)
                                ForEach(Array((reply.sources ?? []).enumerated()), id: \.offset) { _, source in
                                    if let link = source.link {
                                        Link(source.displayName ?? link.host ?? "Source", destination: link)
                                            .font(.caption).accessibilityIdentifier("analyst-source-link")
                                            .accessibilityValue(link.absoluteString)
                                    }
                                }
                            } else if let error = message.error {
                                Text(verbatim: error).foregroundStyle(.red).accessibilityIdentifier(message.id == archive.current.turns.last?.id ? "analyst-error" : "analyst-previous-error")
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
            // Keep a draft focused while the transcript scrolls or adjusts for the keyboard.
            // Sending still dismisses explicitly through the composer FocusState.
            .scrollDismissesKeyboard(.never)
            .onAppear { scroll.scrollTo("chat-bottom", anchor: .bottom) }
            .onChange(of: archive.current.turns.count) { _, _ in withAnimation { scroll.scrollTo("chat-bottom", anchor: .bottom) } }
            .onChange(of: sending) { _, value in if !value { withAnimation { scroll.scrollTo("chat-bottom", anchor: .bottom) } } }
            .onChange(of: archive.selectedID) { _, _ in scroll.scrollTo("chat-bottom", anchor: .bottom) }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .task(id: "\(visible)-\(scenePhase == .active)-\(archive.current.turns.isEmpty)-\(en)") {
            guard visible, scenePhase == .active, archive.current.turns.isEmpty else { return }
            await LaunchGate.wait()
            guard !Task.isCancelled else { return }
            welcome = nil
            while !Task.isCancelled {
                if let value = try? await API.shared.analystWelcome(language: en ? "en" : "ar"), !Task.isCancelled { welcome = value }
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .onChange(of: writing) { _, focused in
            composerLog.info("focus changed focused=\(focused, privacy: .public)")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(en ? "Conversations" : "المحادثات", systemImage: "clock.arrow.circlepath") { showingHistory = true }
                    .accessibilityIdentifier("analyst-history")
                    .accessibilityLabel(Text(verbatim: en ? "Conversations" : "المحادثات")).disabled(sending)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(en ? "New conversation" : "محادثة جديدة", systemImage: "square.and.pencil") { newConversation() }
                    .accessibilityIdentifier("analyst-new-chat")
                    .accessibilityLabel(Text(verbatim: en ? "New conversation" : "محادثة جديدة")).disabled(sending)
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
                    .accessibilityLabel(Text(verbatim: en ? "Football question" : "سؤال عن كرة القدم"))
                    .onChange(of: question) { _, value in
                        composerLog.info("text changed characters=\(value.count, privacy: .public)")
                        if value.count > 1000 { question = String(value.prefix(1000)) }
                    }
                Button { Task { await send() } } label: { Image(systemName: "arrow.up").font(.headline).frame(width: 28, height: 28) }
                    .buttonStyle(.glassProminent).accessibilityLabel(Text(verbatim: en ? "Send" : "إرسال"))
                    .disabled(sending || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("analyst-send")
            }.padding(12).glassEffect(.regular, in: .rect(cornerRadius: 25))
        }.padding(.horizontal).padding(.vertical, 8)
    }
    private func newConversation() {
        archive.newConversation(); question = ""
    }
    @MainActor private func send() async {
        composerLog.info("send invoked busy=\(sending, privacy: .public) characters=\(question.count, privacy: .public)")
        guard !sending else { return }
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let conversationID = archive.selectedID else { return }
        let history = archive.current.history
        let context = archive.current.context
        writing = false; sending = true; question = ""
        let message = AnalystTurn(question: text)
        archive.append(message, context: context)
        composerLog.info("message appended turns=\(archive.current.turns.count, privacy: .public)")
        defer { sending = false }
        do {
            let reply = try await API.shared.askAnalyst(text, context: context, history: history)
            archive.finish(conversation: conversationID, turn: message.id, reply: reply)
            composerLog.info("reply stored characters=\(reply.answer.count, privacy: .public) model=\(reply.model, privacy: .public)")
        } catch {
            composerLog.info("reply failed code=\((error as NSError).code, privacy: .public)")
            let messageText = AnalystNetworkFailure.message(for: error, english: en) ?? error.localizedDescription
            archive.finish(conversation: conversationID, turn: message.id, error: messageText)
            composerLog.info("failure stored")
        }
    }
}
