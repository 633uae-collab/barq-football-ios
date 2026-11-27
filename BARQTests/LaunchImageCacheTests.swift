import UIKit
import XCTest
@testable import BARQ

final class LaunchImageCacheTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
    func testBytesSurviveRecreatingCacheAndRemainURLSpecific() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let bytes = Data([1, 2, 3, 4])
        try LaunchImageDiskCache(directory: directory).save(bytes, for: "https://example.test/a.png?team=1", now: now)
        let reopened = LaunchImageDiskCache(directory: directory)
        XCTAssertEqual(reopened.load("https://example.test/a.png?team=1", now: now.addingTimeInterval(1)), bytes)
        XCTAssertNil(reopened.load("https://example.test/a.png?team=2", now: now.addingTimeInterval(1)))
    }
    func testExpiredOrFutureDatedImageCannotPopulateFirstLayout() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var cache = LaunchImageDiskCache(directory: directory)
        cache.maximumAge = 60
        try cache.save(Data([1]), for: "logo", now: now)
        XCTAssertNotNil(cache.load("logo", now: now.addingTimeInterval(60)))
        XCTAssertNil(cache.load("logo", now: now.addingTimeInterval(61)))
        XCTAssertNil(cache.load("logo", now: now.addingTimeInterval(-1)))
    }
    func testBoundedCacheEvictsOldestEntry() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var cache = LaunchImageDiskCache(directory: directory)
        cache.maximumBytes = 6
        try cache.save(Data([1, 2, 3, 4]), for: "old", now: now)
        try cache.save(Data([5, 6, 7, 8]), for: "new", now: now.addingTimeInterval(1))
        XCTAssertNil(cache.load("old", now: now.addingTimeInterval(2)))
        XCTAssertEqual(cache.load("new", now: now.addingTimeInterval(2)), Data([5, 6, 7, 8]))
    }
    func testOversizedBytesDoNotReplaceUsableImage() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var cache = LaunchImageDiskCache(directory: directory)
        cache.maximumEntryBytes = 4
        try cache.save(Data([1]), for: "logo", now: now)
        try cache.save(Data(repeating: 2, count: 5), for: "logo", now: now)
        XCTAssertEqual(cache.load("logo", now: now), Data([1]))
    }
    func testFreshInstallCanPrepareEveryBundledClubLogoWithoutNetwork() async {
        let addresses = ClubDirectory.bundled.compactMap(\.logo)
        let images = await LaunchHomeCache.shared.prepareCachedImages(addresses)
        XCTAssertEqual(images.count, addresses.count)
        for address in addresses {
            XCTAssertGreaterThan(images[address]?.size.width ?? 0, 0)
        }
    }

    func testPickerCrestsDecodeOfflineAndKeepTeamAndCompetitionIDsSeparate() throws {
        let base = "https://media.api-sports.io/football"
        func crest(_ path: String) throws -> UIImage {
            let url = try XCTUnwrap(URL(string: base + "/" + path))
            return try XCTUnwrap(PickerCrestStore.shared.image(for: url), path)
        }
        _ = try crest("teams/529.png")
        _ = try crest("teams/2865.png")
        _ = try crest("leagues/140.png")
        _ = try crest("leagues/2.png")
        let arsenal = try crest("teams/42.png")
        let leagueTwo = try crest("leagues/42.png")
        XCTAssertNotEqual(try XCTUnwrap(arsenal.pngData()), try XCTUnwrap(leagueTwo.pngData()))
        let otherHost = try XCTUnwrap(URL(string: "https://example.org/football/teams/529.png"))
        XCTAssertNil(PickerCrestStore.shared.image(for: otherHost))
    }
}
