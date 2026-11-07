import XCTest

/// Compare real provider goals and physical team/number adjacency in both languages.
/// No fixture scores are invented or injected into the application.
@MainActor
final class ScoreAssociationUITests: XCTestCase {
    struct Envelope: Decodable { let match: Match }
    struct Match: Decodable {
        struct Team: Decodable { let id: Int; let name: String }
        struct Goals: Decodable { let home: Int?; let away: Int? }
        let id: Int; let home: Team; let away: Team; let goals: Goals
    }
    func testRealResultsRemainBesideTheirTeamsInArabicAndEnglish() async throws {
        continueAfterFailure = false
        let directory = URL(fileURLWithPath: "/tmp/fotiq-launch-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Madrid away, Barcelona home, Madrid home, and two unrelated clubs.
        for id in [1570451, 1570426, 1635716, 1575218] {
            let url = URL(string: "https://barq-football-ios.onrender.com/api/match/\(id)")!
            let (data, response) = try await URLSession.shared.data(from: url)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            let f = try JSONDecoder().decode(Envelope.self, from: data).match
            XCTAssertEqual(f.id, id)
            let home = try XCTUnwrap(f.goals.home), away = try XCTUnwrap(f.goals.away)
            // Keep the actual source response beside screenshots for independent review.
            try data.write(to: directory.appendingPathComponent("score-source-\(id).json"))
            for language in ["ar", "en"] {
                let app = XCUIApplication.fotiq()
                app.launchArguments = ["-screen", "match", "-id", String(id), "-lang", language]
                app.launch()
                let h = app.staticTexts["score-home-\(id)"]
                let a = app.staticTexts["score-away-\(id)"]
                XCTAssertTrue(h.waitForExistence(timeout: 90))
                XCTAssertTrue(a.exists)
                XCTAssertEqual(h.label, String(home), "Home goals: \(f.home.name)")
                XCTAssertEqual(a.label, String(away), "Away goals: \(f.away.name)")
                let ht = app.staticTexts["score-team-\(id)-\(f.home.id)"]
                let at = app.staticTexts["score-team-\(id)-\(f.away.id)"]
                XCTAssertTrue(ht.exists); XCTAssertTrue(at.exists)
                // Read geometry from one immutable tree; refresh must not mix frames.
                let snapshot = try app.snapshot()
                func find(_ id: String, in node: XCUIElementSnapshot) -> XCUIElementSnapshot? {
                    if node.identifier == id { return node }
                    for child in node.children { if let match = find(id, in: child) { return match } }
                    return nil
                }
                let hg = try XCTUnwrap(find("score-home-\(id)", in: snapshot))
                let ag = try XCTUnwrap(find("score-away-\(id)", in: snapshot))
                let htFrame = try XCTUnwrap(find("score-team-\(id)-\(f.home.id)", in: snapshot)).frame
                let atFrame = try XCTUnwrap(find("score-team-\(id)-\(f.away.id)", in: snapshot)).frame
                XCTAssertGreaterThan((hg.frame.midX - ag.frame.midX) * (htFrame.midX - atFrame.midX), 0,
                                     "Goals must follow the same physical order as their teams")
                if language == "ar" { XCTAssertGreaterThan(htFrame.midX, atFrame.midX) }
                else { XCTAssertLessThan(htFrame.midX, atFrame.midX) }
                let screenshot = app.screenshot()
                let name = "score-\(id)-\(language)"
                try screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"))
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
                if id == 1570451 && language == "ar" {
                    let save = app.buttons["match-save"]
                    XCTAssertTrue(save.exists)
                    if save.value as? String != "saved" { save.tap() }
                    XCTAssertEqual(save.value as? String, "saved")
                    app.terminate()
                    app.launchArguments = ["-startTab", "favorites", "-lang", language]
                    app.launch()
                    XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
                    let savedHome = app.staticTexts["score-home-\(id)"]
                    let savedAway = app.staticTexts["score-away-\(id)"]
                    XCTAssertTrue(savedHome.waitForExistence(timeout: 90))
                    XCTAssertEqual(savedHome.label, String(home))
                    XCTAssertEqual(savedAway.label, String(away))
                    let tree = try app.snapshot()
                    let left = try XCTUnwrap(find("score-away-\(id)", in: tree)).frame
                    let right = try XCTUnwrap(find("score-home-\(id)", in: tree)).frame
                    let homeTeam = try XCTUnwrap(find("score-team-\(id)-\(f.home.id)", in: tree)).frame
                    let awayTeam = try XCTUnwrap(find("score-team-\(id)-\(f.away.id)", in: tree)).frame
                    XCTAssertGreaterThan(right.midX, left.midX)
                    XCTAssertGreaterThan(homeTeam.midX, awayTeam.midX)
                    try app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("score-madrid-saved-ar.png"))
                }
                app.terminate()
            }
        }
    }
}
