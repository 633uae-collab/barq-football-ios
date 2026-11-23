import XCTest

extension XCTestCase {
    func recording(_ action: String, phase: String = "") throws {
        let control = ProcessInfo.processInfo.environment["FOTIQ_RECORDING_CONTROL"] ?? "/tmp/fotiq-core-recording"
        let directory = URL(fileURLWithPath: control, isDirectory: true)
        guard ProcessInfo.processInfo.environment["FOTIQ_RECORD_VIDEO"] == "1" else { return }
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("enabled").path) else {
            throw NSError(domain: "CoreRecording", code: 3, userInfo: [NSLocalizedDescriptionKey: "Explicit video pass requires a recorder"])
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let udid = try XCTUnwrap(ProcessInfo.processInfo.environment["SIMULATOR_UDID"], "Record the actual XCTest simulator")
        let deadline = Date().addingTimeInterval(20)
        let request: [String: Any] = ["id": id, "action": action, "phase": phase, "udid": udid,
                                      "requestedAt": Date().timeIntervalSince1970,
                                      "expiresAt": deadline.timeIntervalSince1970]
        try JSONSerialization.data(withJSONObject: request).write(to: directory.appendingPathComponent("request.json"), options: .atomic)
        while Date() < deadline {
            if let data = try? Data(contentsOf: directory.appendingPathComponent("ack.json")),
               let ack = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               ack["id"] as? String == id {
                guard ack["ok"] as? Bool == true else {
                    throw NSError(domain: "CoreRecording", code: 1, userInfo: [NSLocalizedDescriptionKey: ack["error"] as? String ?? "Recorder failed"])
                }
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        // A timed-out start must not begin recording after XCTest tears down the app.
        try? Data().write(to: directory.appendingPathComponent("cancelled-\(id)"), options: .atomic)
        throw NSError(domain: "CoreRecording", code: 2, userInfo: [NSLocalizedDescriptionKey: "Recorder acknowledgment missing"])
    }
}
