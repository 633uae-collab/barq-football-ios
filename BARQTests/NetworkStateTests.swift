import XCTest
@testable import BARQ

/// URLProtocol stub: simulates no network, server errors and partial match data without touching the real backend.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var mode: Mode = .offline
    enum Mode { case offline, status(Int, String), body(String) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        switch Self.mode {
        case .offline: client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .status(let c, let b):
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: c, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(b.utf8)); client?.urlProtocolDidFinishLoading(self)
        case .body(let b):
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(b.utf8)); client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

final class NetworkStateTests: XCTestCase {
    func api() -> API { API(protocolClasses: [StubProtocol.self], fixedBase: "https://stub.local") }

    func testOfflineGivesClearMessage() async {
        StubProtocol.mode = .offline
        do { let _: FixturesResponse = try await api().get("/api/fixtures"); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? APIError, .offline); XCTAssertFalse(error.localizedDescription.isEmpty) }
    }
    func testServerErrorMessagePassedThrough() async {
        StubProtocol.mode = .status(503, #"{"error":"PLAN_LIMIT"}"#)
        do { let _: FixturesResponse = try await api().get("/api/fixtures"); XCTFail("should throw") }
        catch { XCTAssertEqual(error.localizedDescription, "PLAN_LIMIT") }
    }
    func testMatchWithoutLineupsOrStatsStillDecodes() async throws {
        StubProtocol.mode = .body(#"{"match":{"id":9,"date":"","ts":0,"status":{"short":"NS"},"league":{"id":1,"name":"L"},"home":{"id":1,"name":"A"},"away":{"id":2,"name":"B"},"goals":{"home":null,"away":null}},"events":[],"lineups":[],"statistics":[]}"#)
        let d: MatchDetail = try await api().get("/api/match/9")
        XCTAssertTrue(d.lineups.isEmpty); XCTAssertTrue(d.statistics.isEmpty); XCTAssertTrue(d.match.isUpcoming)
    }
    func testFavouritesAndSavedMatchesPersist() {
        let d = UserDefaults.standard
        let oldT = d.data(forKey: "favTeams"), oldS = d.data(forKey: "savedMatches")
        defer { d.set(oldT, forKey: "favTeams"); d.set(oldS, forKey: "savedMatches") }
        let s = AppStore()
        s.favTeams = []; s.savedMatches = []
        s.toggleFav(TeamRef(id: 40, name: "Liverpool", logo: nil, winner: nil))
        s.toggleSaved(1557453)
        let reloaded = AppStore()
        XCTAssertEqual(reloaded.favTeams.map(\.id), [40])
        XCTAssertEqual(reloaded.savedMatches, [1557453])
    }
}

extension APIError: Equatable {
    public static func == (a: APIError, b: APIError) -> Bool { a.localizedDescription == b.localizedDescription }
}
