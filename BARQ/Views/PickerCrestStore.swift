import Foundation
import SQLite3
import UIKit

/// A club and a competition can share the same ID. Only canonical URLs from the
/// existing provider participate in the bundled lookup.
final class PickerCrestStore {
    static let shared = PickerCrestStore()
    private let database: OpaquePointer?
    private let lock = NSLock()

    private init() {
        var opened: OpaquePointer?
        if let file = Bundle.main.url(forResource: "PickerCrests", withExtension: "sqlite"),
           sqlite3_open_v2(file.path, &opened, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            database = opened
        } else {
            sqlite3_close(opened)
            database = nil
        }
    }

    deinit { sqlite3_close(database) }

    func image(for url: URL) -> UIImage? {
        let path = url.pathComponents
        guard path.count == 4, path[1] == "football",
              path[2] == "teams" || path[2] == "leagues",
              let id = Int64(url.deletingPathExtension().lastPathComponent), id > 0,
              url.absoluteString == "https://media.api-sports.io/football/\(path[2])/\(id).png",
              let database else { return nil }
        let data: Data? = lock.withLock {
            var query: OpaquePointer?
            guard sqlite3_prepare_v2(database, "SELECT image FROM crest WHERE kind=? AND id=?", -1, &query, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(query) }
            return path[2].withCString { kind -> Data? in
                defer { sqlite3_clear_bindings(query) }
                guard sqlite3_bind_text(query, 1, kind, -1, nil) == SQLITE_OK,
                      sqlite3_bind_int64(query, 2, id) == SQLITE_OK,
                      sqlite3_step(query) == SQLITE_ROW,
                      let bytes = sqlite3_column_blob(query, 0) else { return nil }
                return Data(bytes: bytes, count: Int(sqlite3_column_bytes(query, 0)))
            }
        }
        guard let data, let image = UIImage(data: data) else { return nil }
        return image.preparingForDisplay() ?? image
    }
}
