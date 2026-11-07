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
    func testCameraClockUsesElapsedTimeWithoutFrameClamp() {
        let clock = SplashClock()
        XCTAssertEqual(clock.tick(100), 0)
        XCTAssertEqual(clock.tick(100.1), 0.1, accuracy: 0.0001)
        XCTAssertEqual(clock.tick(101.75), 1.75, accuracy: 0.0001)
    }
    func testCameraClockDoesNotConsumeTransitionWhileDestinationIsPreparing() {
        let clock = SplashClock()
        XCTAssertEqual(clock.tick(100, active: false), 0)
        XCTAssertEqual(clock.tick(102, active: false), 0)
        XCTAssertEqual(clock.tick(104, active: true), 0)
        XCTAssertEqual(clock.tick(104.3, active: true), 0.3, accuracy: 0.0001)
        XCTAssertEqual(clock.largestFrameGap, 0.3, accuracy: 0.0001)
    }
    func testApertureStartsClosedAndEndsBeyondEntirePhoneViewport() {
        for size in [CGSize(width: 375, height: 812), CGSize(width: 440, height: 956)] {
            XCTAssertEqual(SplashView.aperture(t: 0, size: size).width, 0)
            XCTAssertTrue(SplashView.aperture(t: 1, size: size).contains(CGRect(origin: .zero, size: size)))
            XCTAssertEqual(SplashView.scale(0), 1)
            XCTAssertEqual(SplashView.scale(1), SplashView.maxScale, accuracy: 0.001)
        }
        XCTAssertGreaterThanOrEqual(SplashView.hold + SplashView.push, 1.5)
        XCTAssertLessThanOrEqual(SplashView.hold + SplashView.push, 2)
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
    func testSkippingClubsCanResumeCompetitionStepWithoutLosingPicks() {
        let name = "premium-\(UUID())", d = UserDefaults(suiteName: "premium-test")!
        defer { d.removePersistentDomain(forName: "premium-test") }
        Onboarding.saveDraft(.init(step: 1, clubs: [], leagues: [39], cups: []), d)
        XCTAssertEqual(Onboarding.loadDraft(d).step, 1, name)
        XCTAssertEqual(Onboarding.loadDraft(d).leagues, [39])
    }
}
