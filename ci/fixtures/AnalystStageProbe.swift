import Foundation
import OSLog

// Disposable synthetic build only. Measures synchronous work; does not move it
// across actors or log questions, responses, file paths or provider data.
enum AnalystStageProbe {
    private static let log = Logger(subsystem: "ae.barq.composer", category: "stage-profile")
    static func measure<T>(_ stage: String, _ body: () throws -> T) rethrows -> T {
        let span = UUID().uuidString
        let start = ProcessInfo.processInfo.systemUptime
        log.info("stage begin name=\(stage, privacy: .public) span=\(span, privacy: .public) main=\(Thread.isMainThread, privacy: .public)")
        defer {
            let micros = Int((ProcessInfo.processInfo.systemUptime - start) * 1_000_000)
            log.info("stage end name=\(stage, privacy: .public) span=\(span, privacy: .public) elapsedUs=\(micros, privacy: .public)")
        }
        return try body()
    }
}
