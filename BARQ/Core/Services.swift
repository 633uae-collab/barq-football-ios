import Foundation
import UserNotifications
import ActivityKit
import EventKit
import UIKit

// MARK: Push + local notifications
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    /// APNs device token -> backend. Requires a paid Apple Developer account + aps-environment entitlement.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        let device = UserDefaults.standard.string(forKey: "deviceId") ?? ""
        Task { try? await API.shared.send("POST", "/api/push/register", body: PushRegistration(device: device, kind: "apns", token: hex, fixture: nil)) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error.localizedDescription)")
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let id = response.notification.request.content.userInfo["fixture"] as? Int {
            await MainActor.run { DeepLink.shared.fixtureId = id }
        }
    }
}

struct PushRegistration: Codable { var device: String; var kind: String; var token: String; var fixture: Int? }

@Observable final class DeepLink { static let shared = DeepLink(); var fixtureId: Int? }

enum Notifier {
    static func requestPermission() async -> Bool {
        let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if ok { await MainActor.run { UIApplication.shared.registerForRemoteNotifications() } }
        return ok
    }
    /// Maps an AI analyst insight to a local notification (same fields the backend puts in the APNs payload).
    static func content(for i: Insight) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = i.title
        c.body = i.body
        c.threadIdentifier = "fixture-\(i.fixture)"
        c.userInfo = ["fixture": i.fixture, "insight": i.id, "type": i.type]
        c.interruptionLevel = i.level == "high" ? .timeSensitive : .active
        c.sound = .default
        return c
    }
    static func post(_ i: Insight) {
        let req = UNNotificationRequest(identifier: "insight-\(i.id)", content: content(for: i), trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
    /// Density filter: 0 = only red/ht/ft (low noise), 1 = + medium, 2 = all.
    static func allowed(_ i: Insight, density: Int) -> Bool {
        switch density {
        case 0: return i.level == "low"
        case 1: return i.level != "high" || i.type == "possession"
        default: return true
        }
    }
}

// MARK: Live Activities
enum LiveActivities {
    static var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    static func short(_ name: String) -> String { String(name.replacingOccurrences(of: " ", with: "").prefix(3)).uppercased() }

    @discardableResult
    static func start(for f: Fixture) throws -> String {
        if let existing = Activity<MatchActivityAttributes>.activities.first(where: { $0.attributes.fixtureId == f.id }) { return existing.id }
        let attrs = MatchActivityAttributes(fixtureId: f.id, league: f.league.name, homeName: f.home.name, awayName: f.away.name,
                                            homeShort: short(f.home.name), awayShort: short(f.away.name))
        let state = MatchActivityAttributes.ContentState(homeGoals: f.goals.home ?? 0, awayGoals: f.goals.away ?? 0,
                                                         minute: f.status.elapsed ?? 0, status: f.status.short, lastEvent: nil, insight: nil)
        // pushType .token -> per-activity APNs token sent to backend (needs paid account to actually receive pushes).
        let act = try Activity.request(attributes: attrs, content: .init(state: state, staleDate: Date().addingTimeInterval(600)), pushType: .token)
        Task {
            for await tok in act.pushTokenUpdates {
                let hex = tok.map { String(format: "%02x", $0) }.joined()
                try? await API.shared.send("POST", "/api/push/register", body: PushRegistration(device: UserDefaults.standard.string(forKey: "deviceId") ?? "", kind: "liveactivity", token: hex, fixture: f.id))
            }
        }
        return act.id
    }

    /// Local (in-app) update path used while the app is foreground; background updates come via APNs.
    static func update(_ f: Fixture, insight: String? = nil) async {
        for a in Activity<MatchActivityAttributes>.activities where a.attributes.fixtureId == f.id {
            let s = MatchActivityAttributes.ContentState(homeGoals: f.goals.home ?? 0, awayGoals: f.goals.away ?? 0, minute: f.status.elapsed ?? 0,
                                                         status: f.status.short, lastEvent: nil, insight: insight ?? a.content.state.insight)
            if f.isDone { await a.end(.init(state: s, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(900))) }
            else { await a.update(.init(state: s, staleDate: Date().addingTimeInterval(600))) }
        }
    }

    /// Push-to-start token (iOS 17.2+): lets the backend start a Live Activity when a favourite team kicks off.
    static func observePushToStart() {
        Task {
            for await tok in Activity<MatchActivityAttributes>.pushToStartTokenUpdates {
                let hex = tok.map { String(format: "%02x", $0) }.joined()
                try? await API.shared.send("POST", "/api/push/register", body: PushRegistration(device: UserDefaults.standard.string(forKey: "deviceId") ?? "", kind: "pushtostart", token: hex, fixture: nil))
            }
        }
    }
}

// MARK: iPhone Calendar
enum CalendarService {
    static func add(_ f: Fixture) async throws {
        let store = EKEventStore()
        guard try await store.requestWriteOnlyAccessToEvents() else { throw APIError.server(String(localized: "لم يتم السماح بالوصول للتقويم")) }
        let e = EKEvent(eventStore: store)
        e.title = "\(f.home.name) × \(f.away.name)"
        e.startDate = f.kickoff
        e.endDate = f.kickoff.addingTimeInterval(115 * 60)
        e.location = f.venue
        e.notes = f.league.name
        e.addAlarm(EKAlarm(relativeOffset: -30 * 60))
        e.calendar = store.defaultCalendarForNewEvents
        try store.save(e, span: .thisEvent)
    }
}
