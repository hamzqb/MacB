import XCTest
@testable import MacBCore

final class LidFoldTests: XCTestCase {
    func testTheFoldOnlyStartsOnceTheLidIsPastTheOpenAngle() {
        XCTAssertEqual(LidFold.progress(forAngle: 180), 0)
        XCTAssertEqual(LidFold.progress(forAngle: LidFold.openAngle), 0)
        XCTAssertEqual(LidFold.progress(forAngle: 46), 0.5, accuracy: 0.02)
        XCTAssertEqual(LidFold.progress(forAngle: LidFold.foldedAngle), 1)
        XCTAssertEqual(LidFold.progress(forAngle: 0), 1)
        XCTAssertTrue(LidFold.isClosed(angle: 3))
        XCTAssertFalse(LidFold.isClosed(angle: 30))
    }

    func testAnOpeningIsReportedOnceAndOnlyAfterTheLidWasActuallyShut() {
        var tracker = LidFoldTracker()
        // Typing wobble on an open lid is not an opening.
        for angle in [110.0, 104, 112, 100] {
            XCTAssertEqual(tracker.update(angle: angle), .none)
        }
        XCTAssertEqual(tracker.update(angle: 70), .folding)
        // Still folding, so no second event.
        XCTAssertEqual(tracker.update(angle: 40), .none)
        XCTAssertEqual(tracker.update(angle: 2), .none)
        // Back up, but not far enough to count yet.
        XCTAssertEqual(tracker.update(angle: 20), .none)
        XCTAssertEqual(tracker.update(angle: 95), .opened)
        // The same open lid must not greet again.
        XCTAssertEqual(tracker.update(angle: 100), .none)
        XCTAssertEqual(tracker.update(angle: 60), .folding)
    }

    func testALidThatDipsWithoutClosingNeverGreets() {
        var tracker = LidFoldTracker()
        XCTAssertEqual(tracker.update(angle: 120), .none)
        XCTAssertEqual(tracker.update(angle: 50), .folding)
        XCTAssertEqual(tracker.update(angle: 120), .none)
        XCTAssertEqual(tracker.update(angle: 50), .folding)
    }

    func testASilentSensorFoldsNothingAndForgetsNothing() {
        var tracker = LidFoldTracker()
        XCTAssertEqual(tracker.update(angle: 3), .none)
        XCTAssertEqual(tracker.update(angle: nil), .none)
        XCTAssertEqual(tracker.progress, 0)
        // The lid was shut before the sensor went quiet, so this is still an opening.
        XCTAssertEqual(tracker.update(angle: 100), .opened)
    }

    func testTheGreetingFitsTheTimeOfDay() {
        XCTAssertEqual(IslandEvent.greeting(forHour: 7), "Günaydın")
        XCTAssertEqual(IslandEvent.greeting(forHour: 13), "İyi günler")
        XCTAssertEqual(IslandEvent.greeting(forHour: 20), "İyi akşamlar")
        XCTAssertEqual(IslandEvent.greeting(forHour: 2), "İyi geceler")
        let event = IslandEvent.welcome(hour: 9, time: "09:14", batteryPercent: 78)
        XCTAssertEqual(event.kind, .welcome)
        XCTAssertEqual(event.detail, "09:14 · %78")
        XCTAssertEqual(IslandEvent.welcome(hour: 9, time: "09:14", batteryPercent: nil).detail, "09:14")
    }
}
