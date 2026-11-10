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
}
