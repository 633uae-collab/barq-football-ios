import XCTest
@testable import BARQ

final class P0PersistenceTests: XCTestCase {
    var defaults: UserDefaults!
    var suite: String!
    override func setUp() { suite = "p0-\(UUID())"; defaults = UserDefaults(suiteName: suite)! }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    func payload(_ id: Int) -> PrefsPayload { .init(favTeams: [id], favLeagues: [39], saved: [123]) }

    func testRelaunchKeepsAllLocalPreferencesAndDeviceID() {
        let store = AppStore(defaults: defaults, syncEnabled: false)
        store.favTeams = [.init(id: 40, name: "Liverpool", logo: nil)]
        store.favLeagues = [2, 39]; store.savedMatches = [123, 456]; store.mutedTeams = [40]
        store.homeSections = ["upcoming", "stars", "carousel"]
        store.theme = .light; store.accentKey = "blue"; store.tz = "UTC"; store.alertDensity = 2
        let relaunched = AppStore(defaults: defaults, syncEnabled: false)
        XCTAssertEqual(relaunched.deviceId, store.deviceId)
        XCTAssertEqual(relaunched.favTeams, store.favTeams)
        XCTAssertEqual(relaunched.favLeagues, [2, 39]); XCTAssertEqual(relaunched.savedMatches, [123, 456])
        XCTAssertEqual(relaunched.mutedTeams, [40]); XCTAssertEqual(relaunched.homeSections, store.homeSections)
        XCTAssertEqual(relaunched.theme, .light); XCTAssertEqual(relaunched.accentKey, "blue")
        XCTAssertEqual(relaunched.tz, "UTC"); XCTAssertEqual(relaunched.alertDensity, 2)
    }
    func testUpdateMigrationPreservesCustomSectionOrder() throws {
        let order = ["stars", "carousel", "upcoming"]
        defaults.set(try JSONEncoder().encode(order), forKey: "homeSections")
        defaults.set(try JSONEncoder().encode([40, 50]), forKey: "savedMatches")
        let store = AppStore(defaults: defaults, syncEnabled: false)
        XCTAssertEqual(store.homeSections, order); XCTAssertEqual(store.savedMatches, [40, 50])
    }
    func testCorruptedFavoriteDataRecoversBackup() {
        let store = AppStore(defaults: defaults, syncEnabled: false)
        store.favTeams = [.init(id: 40, name: "Liverpool", logo: nil)]
        defaults.set(Data("broken".utf8), forKey: "favTeams")
        XCTAssertEqual(AppStore(defaults: defaults, syncEnabled: false).favTeams.map(\.id), [40])
    }
    func testClearedFavoritesStayClearedAfterRelaunch() {
        let store = AppStore(defaults: defaults, syncEnabled: false)
        store.favTeams = [.init(id: 40, name: "Liverpool", logo: nil)]
        store.favTeams = []; store.favLeagues = []
        let reloaded = AppStore(defaults: defaults, syncEnabled: false)
        XCTAssertTrue(reloaded.favTeams.isEmpty); XCTAssertTrue(reloaded.favLeagues.isEmpty)
    }
    func testFailedSyncSurvivesRelaunchAndRetries() async {
        let outbox = PreferencesOutbox(defaults: defaults)
        outbox.enqueue(device: "device", payload: payload(40))
        let failed = PreferencesSync(outbox: outbox, send: { _ in throw APIError.offline })
        let first = await failed.flush(); XCTAssertFalse(first)
        let reopened = PreferencesOutbox(defaults: defaults)
        XCTAssertEqual(reopened.pending()?.payload.favTeams, [40])
        let successful = PreferencesSync(outbox: reopened, send: { _ in })
        let second = await successful.flush(); XCTAssertTrue(second); XCTAssertNil(reopened.pending())
    }
    func testOldAcknowledgementDoesNotDiscardNewEdit() {
        let outbox = PreferencesOutbox(defaults: defaults)
        outbox.enqueue(device: "device", payload: payload(40))
        let first = outbox.pending()!
        outbox.enqueue(device: "device", payload: payload(50))
        outbox.acknowledge(first.revision)
        XCTAssertEqual(outbox.pending()?.payload.favTeams, [50])
    }
    func testEditsDuringInFlightWriteAreSentInOrder() async {
        let outbox = PreferencesOutbox(defaults: defaults)
        outbox.enqueue(device: "device", payload: payload(40))
        let recorder = DeliveryRecorder()
        let sync = PreferencesSync(outbox: outbox, send: { entry in
            await recorder.append(entry.payload.favTeams)
            if entry.payload.favTeams == [40] {
                outbox.enqueue(device: "device", payload: .init(favTeams: [50], favLeagues: [], saved: []))
            }
            try await Task.sleep(for: .milliseconds(20))
        })
        async let a = sync.flush()
        async let b = sync.flush()
        _ = await (a, b)
        let delivered = await recorder.values
        XCTAssertEqual(delivered, [[40], [50]]); XCTAssertNil(outbox.pending())
    }
}

private actor DeliveryRecorder {
    var values: [[Int]] = []
    func append(_ ids: [Int]) { values.append(ids) }
}
