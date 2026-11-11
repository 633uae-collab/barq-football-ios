import Foundation
import Observation

struct AnalystTurn: Codable, Identifiable {
    var id = UUID()
    var question: String
    var answer: AnalystReply?
    var error: String?
}
struct AnalystConversation: Codable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var turns: [AnalystTurn] = []
    var context = AnalystContext()
    var title: String { turns.first?.question ?? (L.lang == "en" ? "New conversation" : "محادثة جديدة") }
    /// The JSON server validates JavaScript string.length (UTF-16 units), not
    /// Swift grapheme count. Keep whole characters without exceeding that limit.
    static func boundedContext(_ text: String, utf16Limit: Int) -> String {
        var result = "", used = 0
        for character in text {
            let length = String(character).utf16.count
            guard used + length <= utf16Limit else { break }
            result.append(character); used += length
        }
        return result
    }
    var history: [AnalystHistoryMessage] {
        // Older messages remain readable locally. Only a bounded recent window is
        // transmitted; previous answers are context, never fresh football evidence.
        Array(turns.filter { $0.answer != nil }.suffix(4)).flatMap {
            [AnalystHistoryMessage(role: "user", content: Self.boundedContext($0.question, utf16Limit: 500)),
             AnalystHistoryMessage(role: "assistant", content: Self.boundedContext($0.answer?.answer ?? "", utf16Limit: 1000))]
        }
    }
}
@MainActor @Observable final class AnalystConversations {
    private(set) var conversations: [AnalystConversation] = []
    var selectedID: UUID?
    var storageError: String?
    private let url: URL
    // A failed read must never be followed by a write over the unread archive.
    private var loadingFailed = false
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("analyst-conversations.json")
        if FileManager.default.fileExists(atPath: self.url.path) {
            do { conversations = try JSONDecoder().decode([AnalystConversation].self, from: Data(contentsOf: self.url)) }
            catch {
                loadingFailed = true
                storageError = L.lang == "en"
                    ? "Saved conversations could not be opened. The original file is preserved; new messages will not be saved."
                    : "تعذّر فتح المحادثات المحفوظة. الملف الأصلي محفوظ؛ لن تُحفظ الرسائل الجديدة."
            }
        }
        selectedID = conversations.first?.id
        if conversations.isEmpty { newConversation() }
    }
    var current: AnalystConversation { conversations.first { $0.id == selectedID } ?? AnalystConversation() }
    func newConversation() {
        if let empty = conversations.first(where: { $0.turns.isEmpty }) { selectedID = empty.id; return }
        let conversation = AnalystConversation()
        conversations.insert(conversation, at: 0); selectedID = conversation.id
        save()
    }
    func append(_ turn: AnalystTurn, context: AnalystContext) {
        guard let i = conversations.firstIndex(where: { $0.id == selectedID }) else { return }
        conversations[i].turns.append(turn); conversations[i].context = context; save()
    }
    func finish(conversation: UUID, turn: UUID, reply: AnalystReply? = nil, error: String? = nil) {
        guard let i = conversations.firstIndex(where: { $0.id == conversation }),
              let j = conversations[i].turns.firstIndex(where: { $0.id == turn }) else { return }
        conversations[i].turns[j].answer = reply; conversations[i].turns[j].error = error
        if let context = reply?.context { conversations[i].context = context }
        save()
    }
    func save() {
        guard !loadingFailed else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            storageError = nil
        } catch { storageError = L.lang == "en" ? "Unable to save this conversation on this device." : "تعذّر حفظ المحادثة على هذا الجهاز." }
    }
}
