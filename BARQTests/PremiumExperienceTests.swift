import XCTest
@testable import BARQ

final class PremiumExperienceTests: XCTestCase {
    func testLaunchImagesIncludeVisibleFavoriteBeyondResponsePrefixAndPlayerBadge() {
        let now = Date(timeIntervalSince1970: 1000)
        func fixture(_ id: Int) -> Fixture {
            Fixture(id: id, date: "", ts: 2000 + id,
                status: FixtureStatus(short: "NS"), league: LeagueRef(id: 1, name: "League", logo: "league"),
                home: TeamRef(id: id, name: "Home", logo: "home-\(id)"),
                away: TeamRef(id: id + 100, name: "Away", logo: "away-\(id)"), goals: Goals())
        }
        let fixtures = (1...30).map(fixture)
        let star = StarPlayer(id: 1, name: "Player", photo: "photo", team: TeamRef(id: 999, name: "Team", logo: "badge"),
                              fixture: 30, goals: 0, assists: 0)
        let snapshot = LaunchHomeSnapshot(scope: "test", savedAt: now, today: fixtures, tomorrow: [], stars: [star], lineupsReady: [])
        let addresses = snapshot.visibleImageAddresses(favorites: .init(matches: [30]), now: now)
        XCTAssertTrue(addresses.contains("home-30"))
        XCTAssertTrue(addresses.contains("away-30"))
        XCTAssertTrue(addresses.contains("photo"))
        XCTAssertTrue(addresses.contains("badge"))
        XCTAssertEqual(addresses.count, Set(addresses).count)
    }
    @MainActor func testCancelledLaunchWaiterDoesNotNeedGateToOpen() async {
        LaunchGate.open = false
        defer { LaunchGate.open = true }
        let waiting = Task { await LaunchGate.wait(); return Task.isCancelled }
        await Task.yield()
        waiting.cancel()
        let cancelled = await waiting.value
        XCTAssertTrue(cancelled)
    }
    @MainActor func testOpeningLaunchGateResumesEveryPendingConsumer() async {
        LaunchGate.open = false
        defer { LaunchGate.open = true }
        let consumers = (0..<12).map { index in Task { await LaunchGate.wait(); return index } }
        await Task.yield()
        LaunchGate.open = true
        var results: [Int] = []
        for consumer in consumers { results.append(await consumer.value) }
        XCTAssertEqual(results, Array(0..<12))
    }
    func testPreparationConsumesOnlyTheStationaryReferenceHold() {
        for preparation in [-1.0, 0, 0.2, 0.65, 0.9, 5.0] {
            let credit = PremiumLaunchTrack.holdCredit(displayedFor: preparation, reduceMotion: false)
            XCTAssertGreaterThanOrEqual(credit, 0)
            XCTAssertLessThanOrEqual(credit, PremiumLaunchTrack.hold)
            let pose = PremiumLaunchTrack.pose(at: credit, in: CGSize(width: 402, height: 874))
            XCTAssertEqual(pose.scale, 1)
            XCTAssertEqual(pose.yaw, 0)
            XCTAssertEqual(pose.pitch, 0)
        }
        XCTAssertEqual(PremiumLaunchTrack.holdCredit(displayedFor: 5, reduceMotion: true), 0.5)
        let clock = SplashClock()
        _ = clock.tick(10, active: false)
        XCTAssertEqual(clock.displayedFor(at: 11), 1)
        clock.begin(at: 11, timelineOffset: 2.0 / 3)
        XCTAssertEqual(clock.tick(11.2), 2.0 / 3 + 0.2, accuracy: 0.00001)
        XCTAssertEqual(clock.activeDuration, 0.2, accuracy: 0.00001)
    }
    func testLaunchCacheRejectsExpiredFutureAndDifferentBackendResponses() {
        let now = Date(timeIntervalSince1970: 1000)
        var snapshot = LaunchHomeSnapshot(scope: "production", savedAt: now, today: [], tomorrow: [], stars: nil, lineupsReady: [])
        XCTAssertTrue(snapshot.usable(scope: "production", now: now))
        XCTAssertFalse(snapshot.usable(scope: "offline-test", now: now))
        XCTAssertFalse(snapshot.usable(scope: "production", now: now.addingTimeInterval(121)))
        snapshot.savedAt = now.addingTimeInterval(1)
        XCTAssertFalse(snapshot.usable(scope: "production", now: now))
    }
    func testBrandMarkHasTransparentMatteAndPreservesOriginalColors() throws {
        let resource = try XCTUnwrap(Bundle.main.url(forResource: "PreparedBrandMark", withExtension: "rgba"))
        XCTAssertEqual(try Data(contentsOf: resource).count, 1024 * 1024 * 4)
        let cg = try XCTUnwrap(TransparentBrandMark.image.cgImage)
        let bytes = try XCTUnwrap(cg.dataProvider?.data) as Data
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let offset = y * cg.bytesPerRow + x * 4
            return Array(bytes[offset..<(offset + 4)])
        }
        XCTAssertEqual(pixel(512, 200), [0, 0, 0, 0])
        XCTAssertEqual(pixel(512, 420), [0, 0, 0, 0])
        XCTAssertEqual(pixel(300, 500), [255, 255, 255, 255])
        XCTAssertEqual(pixel(680, 530), [0, 196, 106, 255])
    }
    func testLaunchClockUsesElapsedTimeWithoutFrameClamp() {
        let clock = SplashClock()
        XCTAssertEqual(clock.tick(100), 0)
        XCTAssertEqual(clock.tick(100.1), 0.1, accuracy: 0.0001)
        XCTAssertEqual(clock.tick(101.75), 1.75, accuracy: 0.0001)
    }
    func testLaunchClockDoesNotConsumeTransitionWhileDestinationIsPreparing() {
        let clock = SplashClock()
        XCTAssertEqual(clock.tick(100, active: false), 0)
        XCTAssertEqual(clock.tick(102, active: false), 0)
        XCTAssertEqual(clock.tick(104, active: true), 0)
        XCTAssertEqual(clock.tick(104.3, active: true), 0.3, accuracy: 0.0001)
        XCTAssertEqual(clock.largestFrameGap, 0.3, accuracy: 0.0001)
    }
    func testStaticLaunchKeepsOriginalSizeAndUsesOnlyOpacity() {
        for size in [CGSize(width: 375, height: 812), CGSize(width: 440, height: 956)] {
            let rect = LaunchPresentation.logoRect(in: size)
            XCTAssertEqual(rect.midX, size.width/2, accuracy: 0.001)
            XCTAssertEqual(rect.midY, size.height/2, accuracy: 0.001)
            XCTAssertEqual(rect.width, size.width * 0.38, accuracy: 0.001)
        }
        XCTAssertEqual(LaunchPresentation.opacity(at: 0), 1)
        XCTAssertEqual(LaunchPresentation.opacity(at: 0.5), 1)
        XCTAssertEqual(LaunchPresentation.opacity(at: 0.65), 0.5, accuracy: 0.001)
        XCTAssertEqual(LaunchPresentation.opacity(at: 0.8), 0)
        XCTAssertEqual(LaunchPresentation.duration, 0.8, accuracy: 0.001)
        XCTAssertLessThan(LaunchPresentation.duration, 1)
    }
    func testPortalMovesThroughTheGapAndUncoversTheWholeDestination() {
        XCTAssertEqual(PremiumLaunchTrack.hold, 0.3)
        XCTAssertEqual(PremiumLaunchTrack.duration, 1.5)
        for size in [CGSize(width: 375, height: 812), CGSize(width: 440, height: 956),
                     CGSize(width: 874, height: 402)] {
            var scale: CGFloat = 1
            for frame in 0...180 {
                let pose = PremiumLaunchTrack.pose(at: Double(frame) / 120, in: size)
                XCTAssertGreaterThanOrEqual(pose.scale, scale)
                scale = pose.scale
            }
            XCTAssertLessThan(PremiumLaunchTrack.pose(at: 0.47, in: size).yaw, 0)
            XCTAssertGreaterThan(PremiumLaunchTrack.pose(at: 0.77, in: size).yaw, 0)
            let corners = PremiumLaunchTrack.apertureCorners(at: PremiumLaunchTrack.duration, in: size)
            XCTAssertLessThan(corners[0].x, 0)
            XCTAssertLessThan(corners[0].y, 0)
            XCTAssertGreaterThan(corners[2].x, size.width)
            XCTAssertGreaterThan(corners[2].y, size.height)
        }
    }
    func testTiltedArtworkProjectsAtItsOriginalDepthWithoutCrossingTheCover() {
        let size = CGSize(width: 402, height: 874)
        for time in [0.30, 0.47, 0.77, 1.20] {
            let camera = PremiumLaunchTrack.transform(PremiumLaunchTrack.pose(at: time, in: size))
            for z: CGFloat in [0, -2, -7] {
                let face = PremiumLaunchTrack.faceTransform(camera, depth: z)
                XCTAssertEqual(face.m13, 0)
                XCTAssertEqual(face.m23, 0)
                XCTAssertEqual(face.m43, 0)
                for point in [CGPoint(x: -72, y: -83), CGPoint(x: 72, y: 83)] {
                    let x = point.x, y = point.y
                    let w = x * camera.m14 + y * camera.m24 + z * camera.m34 + camera.m44
                    let flatW = x * face.m14 + y * face.m24 + face.m44
                    let px = (x * camera.m11 + y * camera.m21 + z * camera.m31 + camera.m41) / w
                    let py = (x * camera.m12 + y * camera.m22 + z * camera.m32 + camera.m42) / w
                    XCTAssertEqual((x * face.m11 + y * face.m21 + face.m41) / flatW, px, accuracy: 0.00001)
                    XCTAssertEqual((x * face.m12 + y * face.m22 + face.m42) / flatW, py, accuracy: 0.00001)
                }
            }
        }
    }
    func testLaunchMaskDoesNotClipAnyOriginalArtwork() throws {
        let cg = try XCTUnwrap(TransparentBrandMark.image.cgImage)
        let bytes = try XCTUnwrap(cg.dataProvider?.data) as Data
        // Check every nontransparent original pixel, including antialiasing.
        for y in 255..<769 {
            for x in 285..<740 where bytes[y * cg.bytesPerRow + x * 4 + 3] > 4 {
                let point = CGPoint(x: (Double(x - 285) + 0.5) / 455, y: (Double(y - 255) + 0.5) / 514)
                XCTAssertFalse(PremiumLaunchTrack.aperture.contains(point), "Clipped original pixel \(x),\(y)")
            }
        }
    }
    func meta(_ id: Int, kind: String, active: Bool = true) -> LeagueMeta {
        LeagueMeta(id: id, name: "competition", ar: nil, logo: nil, country: nil, countryAr: nil, continent: nil, group: nil, season: nil, type: kind, active: active)
    }
    func testPriorityAndAllOtherCompetitionsAreKeptWithoutDuplicates() {
        for (kind, ids) in [("League", CompetitionOrder.leagues), ("Cup", CompetitionOrder.cups)] {
            let input = [meta(999, kind: kind, active: false)] + ids.reversed().map { meta($0, kind: kind) } + [meta(ids[0], kind: kind)]
            let output = CompetitionOrder.sorted(input, kind: kind)
            XCTAssertEqual(output.map(\.id), ids + [999])
            XCTAssertEqual(output.last?.active, false)
        }
    }
    func testEmptyClubDraftReturnsToClubsWithoutLosingCompetitionPicks() {
        let name = "premium-\(UUID())", d = UserDefaults(suiteName: "premium-test")!
        defer { d.removePersistentDomain(forName: "premium-test") }
        Onboarding.saveDraft(.init(step: 1, clubs: [], leagues: [39], cups: []), d)
        XCTAssertEqual(Onboarding.loadDraft(d).step, 0, name)
        XCTAssertEqual(Onboarding.loadDraft(d).leagues, [39])
    }
}

