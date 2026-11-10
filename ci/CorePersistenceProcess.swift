import Foundation

// Synthetic offline storage acceptance. Uses unchanged production archive/model
// sources; each mode is invoked as a new OS process by the host workflow.
@main struct CorePersistenceProcess {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "CorePersistenceProcess", code: 1,
                                       userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor static func main() throws {
        let mode = CommandLine.arguments[1]
        let url = URL(fileURLWithPath: CommandLine.arguments[2])
        let archive = AnalystConversations(url: url)
        let context = AnalystContext(fixtureId: 70001, teamIds: [529, 541], playerIds: [7001, 7002])
        let questions = (0..<10).map { $0 % 2 == 0 ? "سؤال تجريبي \($0) ⚽️" : "Synthetic question \($0)" }
        let replies = (0..<10).map { "Synthetic offline reply \($0) — إجابة اختبارية فقط" }
        let kinds = AnalystResponseKind.allCases
        if mode == "write" {
            try require(archive.current.turns.isEmpty, "Writer requires a fresh archive")
            let id = archive.current.id
            for i in 0..<10 {
                let turn = AnalystTurn(question: questions[i])
                archive.append(turn, context: context)
                archive.finish(conversation: id, turn: turn.id, reply: AnalystReply(
                    answer: replies[i], model: kinds[i % kinds.count].rawValue,
                    fetchedAt: Double(i + 1000), generatedAt: Double(i + 2000), context: context,
                    sources: [AnalystSource(name: "Synthetic source \(i)", url: "https://example.org/evidence/\(i)")]))
            }
            try require(archive.storageError == nil, "Write failed")
            print("WRITE_PASS pid=\(ProcessInfo.processInfo.processIdentifier) turns=10 synthetic=true")
            return
        }
        try require(mode == "read" || mode == "followup" || mode == "verify-followup", "Unknown mode")
        let expectedCount = mode == "verify-followup" ? 11 : 10
        try require(archive.storageError == nil, "Read failed")
        try require(archive.current.turns.count == expectedCount, "Unexpected restored turn count")
        for i in 0..<10 {
            let turn = archive.current.turns[i]
            try require(turn.question == questions[i], "Restored question differs")
            try require(turn.answer?.answer == replies[i], "Restored answer differs")
            try require(turn.answer?.model == kinds[i % kinds.count].rawValue, "Restored kind differs")
            try require(turn.answer?.sources?.first?.name == "Synthetic source \(i)", "Source name differs")
            try require(turn.answer?.sources?.first?.url == "https://example.org/evidence/\(i)", "Source URL differs")
            try require(turn.answer?.fetchedAt == Double(i + 1000), "Retrieval timestamp differs")
            try require(turn.answer?.generatedAt == Double(i + 2000), "Generation timestamp differs")
            try require(turn.answer?.context?.teamIds == context.teamIds, "Reply team context differs")
            try require(turn.answer?.context?.playerIds == context.playerIds, "Reply player context differs")
            try require(turn.answer?.context?.fixtureId == context.fixtureId, "Reply context differs")
        }
        try require(archive.current.context.fixtureId == context.fixtureId, "Fixture context lost")
        try require(archive.current.context.teamIds == context.teamIds, "Team context lost")
        try require(archive.current.context.playerIds == context.playerIds, "Player context lost")
        if mode == "followup" {
            try require(archive.current.history.count == 8, "History bound differs")
            try require(archive.current.history.last?.content == replies[9], "Latest restored context differs")
            let turn = AnalystTurn(question: "Synthetic follow-up after process restart")
            archive.append(turn, context: archive.current.context)
            archive.finish(conversation: archive.current.id, turn: turn.id,
                reply: AnalystReply(answer: "Synthetic follow-up response", model: kinds[0].rawValue,
                                    fetchedAt: 3000, generatedAt: 4000, context: context))
            try require(archive.storageError == nil, "Follow-up save failed")
        }
        if mode == "verify-followup" {
            try require(archive.current.turns[10].question == "Synthetic follow-up after process restart", "Follow-up question lost")
            try require(archive.current.turns[10].answer?.answer == "Synthetic follow-up response", "Follow-up answer lost")
        }
        print("\(mode.uppercased())_PASS pid=\(ProcessInfo.processInfo.processIdentifier) turns=\(archive.current.turns.count) synthetic=true")
    }
}
