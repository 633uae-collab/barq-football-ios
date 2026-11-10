import XCTest
@testable import BARQ

final class PremiumExperienceTests: XCTestCase {
    func testPreparationConsumesOnlyTheStationaryReferenceHold() {
        for preparation in [-1.0, 0, 0.2, 0.65, 0.9, 5.0] {
            let credit = PremiumLaunchTrack.holdCredit(displayedFor: preparation, reduceMotion: false)
            XCTAssertGreaterThanOrEqual(credit, 0)
            XCTAssertLessThanOrEqual(credit, PremiumLaunchTrack.firstErase)
            for index in PremiumLaunchTrack.segments.indices {
                XCTAssertEqual(PremiumLaunchTrack.remaining(at: credit, segment: index), 1)
            }
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
            XCTAssertEqual(rect.height * 512 / 514, size.width * 224 / 1320, accuracy: 0.001)
        }
        XCTAssertEqual(LaunchPresentation.opacity(at: 0), 1)
        XCTAssertEqual(LaunchPresentation.opacity(at: 0.5), 1)
        XCTAssertEqual(LaunchPresentation.opacity(at: 0.65), 0.5, accuracy: 0.001)
        XCTAssertEqual(LaunchPresentation.opacity(at: 0.8), 0)
        XCTAssertEqual(LaunchPresentation.duration, 0.8, accuracy: 0.001)
        XCTAssertLessThan(LaunchPresentation.duration, 1)
    }
    func testRiderRevealCoversAllCornersThenContractsMonotonically() {
        for size in [CGSize(width: 375, height: 812), CGSize(width: 440, height: 956)] {
            let radius = PremiumLaunchTrack.coverRadius(at: 0, in: size)
            XCTAssertGreaterThan(radius, hypot(size.width, size.height) / 2)
            XCTAssertEqual(PremiumLaunchTrack.coverRadius(at: 0.8, in: size), radius)
            var previous = radius
            for step in 0...180 {
                let next = PremiumLaunchTrack.coverRadius(at: Double(step) / 100, in: size)
                XCTAssertGreaterThanOrEqual(next, 0)
                XCTAssertLessThanOrEqual(next, previous)
                previous = next
            }
            XCTAssertLessThan(previous, 0.02)
        }
        XCTAssertEqual(PremiumLaunchTrack.duration, 1.8)
    }
    func testRiderEraseIsStationaryAndFinishesBeforeVisibleContraction() {
        for segment in PremiumLaunchTrack.segments.indices {
            XCTAssertEqual(PremiumLaunchTrack.remaining(at: 0.65, segment: segment), 1)
            XCTAssertEqual(PremiumLaunchTrack.remaining(at: 1.05, segment: segment), 0)
            var previous: CGFloat = 1
            for frame in 0...108 {
                let value = PremiumLaunchTrack.remaining(at: Double(frame) / 60, segment: segment)
                XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertLessThanOrEqual(value, previous)
                previous = value
            }
        }
        XCTAssertEqual(PremiumLaunchTrack.pulseOpacity(at: 0), 0)
        XCTAssertGreaterThan(PremiumLaunchTrack.pulseOpacity(at: 1.3), 0)
        XCTAssertEqual(PremiumLaunchTrack.pulseOpacity(at: PremiumLaunchTrack.duration), 0)
        XCTAssertEqual(PremiumLaunchTrack.coverOpacity(at: PremiumLaunchTrack.duration), 0)
    }
    func testLaunchMaskDoesNotClipAnyOriginalArtwork() throws {
        let cg = try XCTUnwrap(TransparentBrandMark.image.cgImage)
        let bytes = try XCTUnwrap(cg.dataProvider?.data) as Data
        // Check every nontransparent original pixel, including antialiasing.
        for y in 255..<769 {
            for x in 285..<740 where bytes[y * cg.bytesPerRow + x * 4 + 3] > 4 {
                let point = CGPoint(x: Double(x - 285) + 0.5, y: Double(y - 255) + 0.5)
                XCTAssertTrue(PremiumLaunchTrack.segments.contains { $0.rect.contains(point) }, "Clipped original pixel \(x),\(y)")
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

