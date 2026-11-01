import ActivityKit
import Foundation

/// Live Activity for one live match (lock screen + Dynamic Island).
/// The same JSON shape is used by APNs `content-state` pushes from the backend.
struct MatchActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var homeGoals: Int
        var awayGoals: Int
        var minute: Int
        var status: String          // e.g. "1H", "HT", "2H", "FT"
        var lastEvent: String?      // e.g. "هدف - صلاح 63'"
        var insight: String?        // latest AI analyst line, data-backed
    }
    var fixtureId: Int
    var league: String
    var homeName: String
    var awayName: String
    var homeShort: String
    var awayShort: String
}
