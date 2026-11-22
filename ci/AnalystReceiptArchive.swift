import Foundation

// Standalone host executable. Staging receipts stay on the machine that runs it.
enum L { static let lang = "ar" }

private struct Receipt: Decodable {
    struct Request: Decodable {
        let question: String
        let context: AnalystContext
    }
    let index: Int
    let status: Int
    let request: Request
    let response: AnalystReply
}

@main
struct AnalystReceiptArchive {
    private static func require(_ ok: Bool, _ message: String) throws {
        if !ok { throw NSError(domain: "PrivateReceiptArchive", code: 1,
                               userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    @MainActor static func main() throws {
        let args = CommandLine.arguments
        try require(args.count == 4, "Expected write or read, receipts JSONL, and a private archive path.")
        let writing = args[1] == "write"
        try require(writing || args[1] == "read", "Unknown mode")
        let url = URL(fileURLWithPath: args[3])
        try require(FileManager.default.fileExists(atPath: url.path) != writing,
                    "Write needs a new archive; read needs an existing archive.")
        let lines = try String(contentsOfFile: args[2], encoding: .utf8).split(separator: "\n")
        try require(!lines.isEmpty, "No receipts")
        let archive = AnalystConversations(url: url)
        let encoder = JSONEncoder()
        for (i, line) in lines.enumerated() {
            let bytes = Data(line.utf8)
            let item = try JSONDecoder().decode(Receipt.self, from: bytes)
            try require(item.index == i + 1 && item.status == 200, "Missing or rejected turn at index \(i + 1)")
            if writing {
                let turn = AnalystTurn(question: item.request.question)
                let id = archive.current.id
                archive.append(turn, context: item.request.context)
                archive.finish(conversation: id, turn: turn.id, reply: item.response)
            }
            try require(archive.current.turns.count > i && archive.storageError == nil, "Archive turn unavailable")
            let restored = archive.current.turns[i]
            try require(restored.question == item.request.question && restored.error == nil, "Question changed")
            let reply = try requireValue(restored.answer)
            let row = try requireValue(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            let raw = try requireValue(row["response"] as? [String: Any])
            let saved = try requireValue(JSONSerialization.jsonObject(with: encoder.encode(reply)) as? [String: Any])
            for key in ["answer","model","sources","context","fetchedAt","generatedAt"] {
                let expected = try requireValue(raw[key] as? NSObject)
                try require(expected.isEqual(saved[key]), "Turn \(i + 1) changed field \(key)")
            }
        }
        try require(archive.current.turns.count == lines.count, "Restored turn count changed")
        struct Continuation: Encodable { let context: AnalystContext; let history: [AnalystHistoryMessage] }
        let next = Continuation(context: archive.current.context, history: archive.current.history)
        FileHandle.standardOutput.write(try encoder.encode(next))
    }

    private static func requireValue<T>(_ value: T?) throws -> T {
        if let value { return value }
        throw NSError(domain: "PrivateReceiptArchive", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Required receipt or archive field is missing."])
    }
}
