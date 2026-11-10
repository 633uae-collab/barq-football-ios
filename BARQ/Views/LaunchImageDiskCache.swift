import Foundation
import CryptoKit

/// Last-seen image bytes for launch preparation. URLCache's deferred disk writes
/// are not a durable handoff across immediate process termination. All calls are
/// serialized by LaunchHomeCache, away from the main actor.
struct LaunchImageDiskCache {
    let directory: URL
    var maximumBytes = 32 * 1024 * 1024
    var maximumEntryBytes = 2 * 1024 * 1024
    var maximumEntries = 256
    var maximumAge: TimeInterval = 24 * 60 * 60

    private func location(_ address: String) -> URL {
        let key = SHA256.hash(data: Data(address.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key)
    }

    func load(_ address: String, now: Date = Date()) -> Data? {
        let file = location(address)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let date = attributes[.modificationDate] as? Date,
              (0...maximumAge).contains(now.timeIntervalSince(date)),
              let size = attributes[.size] as? NSNumber,
              size.intValue <= maximumEntryBytes else { return nil }
        return try? Data(contentsOf: file, options: .mappedIfSafe)
    }

    func save(_ data: Data, for address: String, now: Date = Date()) throws {
        guard !data.isEmpty, data.count <= maximumEntryBytes, data.count <= maximumBytes else { return }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = location(address)
        try data.write(to: file, options: .atomic)
        try manager.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
        let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        let entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize, let date = values.contentModificationDate else { return nil }
            return (url, size, date)
        }.sorted { $0.2 < $1.2 }
        var bytes = entries.reduce(0) { $0 + $1.1 }
        var count = entries.count
        for (url, size, date) in entries {
            if bytes <= maximumBytes, count <= maximumEntries,
               now.timeIntervalSince(date) <= maximumAge { continue }
            try manager.removeItem(at: url)
            bytes -= size; count -= 1
        }
    }
}
