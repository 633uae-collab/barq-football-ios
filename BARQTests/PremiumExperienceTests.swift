import XCTest
@testable import BARQ

final class PremiumExperienceTests: XCTestCase {
    func testBrandMarkHasTransparentMatteAndPreservesOriginalColors() throws {
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
            XCTAssertEqual(rect.width * 0.442, size.width * 0.15, accuracy: 0.001)
        }
        XCTAssertEqual(LaunchPresentation.opacity(at: 0), 1)
        XCTAssertEqual(LaunchPresentation.opacity(at: 0.5), 1)
        XCTAssertEqual(LaunchPresentation.opacity(at: 0.65), 0.5, accuracy: 0.001)
        XCTAssertEqual(LaunchPresentation.opacity(at: 0.8), 0)
        XCTAssertEqual(LaunchPresentation.duration, 0.8, accuracy: 0.001)
        XCTAssertLessThan(LaunchPresentation.duration, 1)
    }
    func testPremiumTrackStartsAtTheOriginalMarkAndEndsBeyondEveryScreenEdge() {
        for size in [CGSize(width: 375, height: 812), CGSize(width: 440, height: 956)] {
            let rect = LaunchPresentation.logoRect(in: size)
            let initial = PremiumLaunchTrack.pose(at: 0, in: size)
            XCTAssertEqual(initial.scale, 1)
            XCTAssertEqual(initial.pitch, 0)
            XCTAssertEqual(initial.yaw, 0)
            XCTAssertFalse(initial.opens)
            XCTAssertEqual(initial.center.x - rect.width * PremiumLaunchTrack.aperture.midX, rect.minX, accuracy: 0.001)
            XCTAssertEqual(initial.center.y - rect.height * PremiumLaunchTrack.aperture.midY, rect.minY, accuracy: 0.001)
            let corners = PremiumLaunchTrack.apertureCorners(at: PremiumLaunchTrack.duration, in: size)
            XCTAssertLessThan(corners[0].x, 0)
            XCTAssertLessThan(corners[0].y, 0)
            XCTAssertGreaterThan(corners[2].x, size.width)
            XCTAssertGreaterThan(corners[2].y, size.height)
            let orbit = PremiumLaunchTrack.pose(at: 0.4, in: size)
            XCTAssertNotEqual(orbit.pitch, 0, "Premium launch includes perspective, not scale alone")
            XCTAssertNotEqual(orbit.yaw, 0)
        }
        XCTAssertEqual(PremiumLaunchTrack.duration, 1.4)
    }
    func testRevealApertureIsInsideTheTransparentGapOfTheActualLogo() throws {
        let cg = try XCTUnwrap(TransparentBrandMark.image.cgImage)
        let bytes = try XCTUnwrap(cg.dataProvider?.data) as Data
        let gap = PremiumLaunchTrack.aperture
        for row in 0...10 {
            for column in 0...10 {
                let x = Int((gap.minX + gap.width * CGFloat(column) / 10) * CGFloat(cg.width))
                let y = Int((gap.minY + gap.height * CGFloat(row) / 10) * CGFloat(cg.height))
                XCTAssertEqual(bytes[y * cg.bytesPerRow + x * 4 + 3], 0, "Reveal must originate in the original F gap")
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
