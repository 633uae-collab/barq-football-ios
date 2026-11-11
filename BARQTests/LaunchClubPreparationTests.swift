import XCTest
@testable import BARQ

final class LaunchClubPreparationTests: XCTestCase {
    private func clubs(_ count: Int) -> [TeamRef] {
        (1...count).map { TeamRef(id: $0, name: "Club \($0)", logo: "https://example.test/\($0).png") }
    }

    func testLargeSavedDirectoryDoesNotDecodeOffscreenTail() {
        let popular = clubs(56)
        let addresses = LaunchClubPreparation.imageAddresses(selected: [], popular: popular,
            viewport: CGSize(width: 402, height: 874))
        // Three columns and nine conservative rows cover the entire viewport,
        // including space actually occupied by headers and footers.
        XCTAssertEqual(addresses, Array(popular.prefix(27).compactMap(\.logo)))
        XCTAssertFalse(addresses.contains(popular.last!.logo!))
    }

    func testSelectedClubsLeadWithoutDuplicatingTheirDirectoryRows() {
        let popular = clubs(40)
        let addresses = LaunchClubPreparation.imageAddresses(selected: [popular[35], popular[0]],
            popular: popular, viewport: CGSize(width: 320, height: 568))
        XCTAssertEqual(addresses.count, 12)
        XCTAssertEqual(Array(addresses.prefix(3)), [popular[35].logo!, popular[0].logo!, popular[1].logo!])
        XCTAssertEqual(Set(addresses).count, addresses.count)
    }

    func testAllBundledLogosFitSmallestSupportedPhoneViewport() {
        let addresses = LaunchClubPreparation.imageAddresses(selected: [], popular: ClubDirectory.bundled,
            viewport: CGSize(width: 320, height: 568))
        XCTAssertEqual(addresses, ClubDirectory.bundled.compactMap(\.logo))
    }

    func testLandscapeUsesItsActualAdaptiveColumnCount() {
        let addresses = LaunchClubPreparation.imageAddresses(selected: [], popular: clubs(56),
            viewport: CGSize(width: 874, height: 402))
        XCTAssertEqual(addresses.count, 35)
    }
}
