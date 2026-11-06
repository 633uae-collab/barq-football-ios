import Foundation

struct PendingPreferences: Codable {
    var revision = UUID()
    var device: String
    var payload: PrefsPayload
}

/// One durable latest snapshot. The lock makes compare-and-remove atomic with UI edits.
final class PreferencesOutbox: @unchecked Sendable {
    static let shared = PreferencesOutbox(defaults: .standard)
    static let key = "preferences.pending.v1"
    private let defaults: UserDefaults
    private let lock = NSLock()
    init(defaults: UserDefaults) { self.defaults = defaults }

    func enqueue(device: String, payload: PrefsPayload) {
        lock.lock(); defer { lock.unlock() }
        if let data = try? JSONEncoder().encode(PendingPreferences(device: device, payload: payload)) {
            defaults.set(data, forKey: Self.key)
        }
    }
    func pending() -> PendingPreferences? {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(PendingPreferences.self, from: data)
    }
    func acknowledge(_ revision: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.key),
              let current = try? JSONDecoder().decode(PendingPreferences.self, from: data),
              current.revision == revision else { return }
        defaults.removeObject(forKey: Self.key)
    }
}

/// Only one write in flight. A later edit is sent AFTER the previous write is acknowledged.
/// Failures retain the outbox across app termination; foreground/relaunch retries it.
actor PreferencesSync {
    static let shared = PreferencesSync(outbox: .shared)
    private let outbox: PreferencesOutbox
    private let send: (PendingPreferences) async throws -> Void
    private var running = false

    init(outbox: PreferencesOutbox, send: @escaping (PendingPreferences) async throws -> Void = { entry in
        try await API.shared.send("PUT", "/api/prefs/\(entry.device)", body: entry.payload)
    }) {
        self.outbox = outbox; self.send = send
    }

    @discardableResult
    func flush() async -> Bool {
        guard !running else { return false }
        running = true; defer { running = false }
        // Bound work if preferences are continuously edited. The next foreground tick drains the rest.
        for _ in 0..<8 {
            guard !Task.isCancelled else { return false }
            guard let entry = outbox.pending() else { return true }
            do { try await send(entry) }
            catch { return false }
            outbox.acknowledge(entry.revision)
        }
        return outbox.pending() == nil
    }
}
