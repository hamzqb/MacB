import XCTest
@testable import MacBCore

final class LidFoldTests: XCTestCase {
    func testTheFoldOnlyStartsOnceTheLidIsPastTheOpenAngle() {
        XCTAssertEqual(LidFold.progress(forAngle: 180), 0)
        XCTAssertEqual(LidFold.progress(forAngle: LidFold.defaultOpenAngle), 0)
        XCTAssertEqual(LidFold.progress(forAngle: 37), 0.5, accuracy: 0.02)
        XCTAssertEqual(LidFold.progress(forAngle: 14), 1)
        XCTAssertEqual(LidFold.progress(forAngle: 0), 1)
        XCTAssertTrue(LidFold.isClosed(angle: 3))
        XCTAssertFalse(LidFold.isClosed(angle: 30))
    }

    func testEveryDegreeOfHingeAddsTheSameAmountOfFold() {
        // A straight line, so the picture tracks the hand turning the lid.
        let step = LidFold.progress(forAngle: 50) - LidFold.progress(forAngle: 55)
        for start in stride(from: 55.0, to: 20.0, by: -5) {
            let delta = LidFold.progress(forAngle: start - 5) - LidFold.progress(forAngle: start)
            XCTAssertEqual(delta, step, accuracy: 0.001)
        }
    }

    func testAChosenAngleMovesTheWholeFoldWithIt() {
        XCTAssertEqual(LidFold.progress(forAngle: 80, openAngle: 100), 0.233, accuracy: 0.01)
        XCTAssertEqual(LidFold.progress(forAngle: 80, openAngle: 60), 0)
        // Out of range choices are pulled back rather than producing nonsense.
        XCTAssertEqual(LidFold.clampOpenAngle(0), LidFold.minimumOpenAngle)
        XCTAssertEqual(LidFold.clampOpenAngle(500), LidFold.maximumOpenAngle)
        XCTAssertEqual(LidFold.progress(forAngle: 30, openAngle: 5), 0)
        // A low starting angle still has room to animate instead of snapping.
        XCTAssertLessThan(LidFold.foldedAngle(openAngle: LidFold.minimumOpenAngle),
                          LidFold.minimumOpenAngle)
        XCTAssertEqual(LidFold.progress(forAngle: 18, openAngle: 20), 0.333, accuracy: 0.01)
    }

    func testAnOpeningIsReportedOnceAndOnlyAfterTheLidWasActuallyShut() {
        var tracker = LidFoldTracker()
        // Typing wobble on an open lid is not an opening.
        for angle in [110.0, 104, 112, 100] {
            XCTAssertEqual(tracker.update(angle: angle), .none)
        }
        XCTAssertEqual(tracker.update(angle: 55), .folding)
        // Still folding, so no second event.
        XCTAssertEqual(tracker.update(angle: 40), .none)
        XCTAssertEqual(tracker.update(angle: 2), .none)
        // Back up, but not far enough to count yet.
        XCTAssertEqual(tracker.update(angle: 20), .none)
        XCTAssertEqual(tracker.update(angle: 95), .opened)
        // The same open lid must not greet again.
        XCTAssertEqual(tracker.update(angle: 100), .none)
        XCTAssertEqual(tracker.update(angle: 55), .folding)
    }

    func testALidThatDipsWithoutClosingNeverGreets() {
        var tracker = LidFoldTracker()
        XCTAssertEqual(tracker.update(angle: 120), .none)
        XCTAssertEqual(tracker.update(angle: 40), .folding)
        XCTAssertEqual(tracker.update(angle: 120), .none)
        XCTAssertEqual(tracker.update(angle: 40), .folding)
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

    // MARK: - Screen blur

    func testTheScreenIsUntouchedUntilTheFoldStarts() {
        XCTAssertEqual(LidScreenBlur.blurAlpha(progress: 0), 0)
        XCTAssertEqual(LidScreenBlur.dimAlpha(progress: 0), 0)
    }

    func testTheScreenIsFullyBlurredBeforeTheLidFinishes() {
        XCTAssertEqual(LidScreenBlur.blurAlpha(progress: 0.92), 1)
        XCTAssertEqual(LidScreenBlur.blurAlpha(progress: 1), 1)
        XCTAssertEqual(LidScreenBlur.dimAlpha(progress: 1), LidScreenBlur.maximumDim, accuracy: 0.0001)
    }

    func testTheBlurOnlyEverDeepensAndFrontLoadsWhatIsSeen() {
        var previous = -1.0
        for step in 0...100 {
            let alpha = LidScreenBlur.blurAlpha(progress: Double(step) / 100)
            XCTAssertGreaterThanOrEqual(alpha, previous)
            previous = alpha
        }
        // Half the fold has to look like more than half the blur, or the screen
        // appears untouched until the last moment and then snaps.
        XCTAssertGreaterThan(LidScreenBlur.blurAlpha(progress: 0.5), 0.6)
        XCTAssertGreaterThan(LidScreenBlur.blurAlpha(progress: 0.25), 0.4)
    }

    func testAHandWrittenLineReplacesTheGreetingWithoutLosingTheDetail() {
        let event = IslandEvent.welcome(hour: 2, time: "09:14", batteryPercent: 78, custom: "Hoş geldin")
        XCTAssertEqual(event.title, "Hoş geldin")
        XCTAssertEqual(event.detail, "09:14 · %78")
        let bye = IslandEvent.farewell(hour: 2, batteryPercent: 72, custom: "  Kendine iyi bak  ")
        XCTAssertEqual(bye.title, "Kendine iyi bak")
        XCTAssertEqual(bye.detail, "%72")
    }

    func testAnEmptyLineLeavesTheTimeOfDayInCharge() {
        XCTAssertNil(IslandEvent.customTitle(nil))
        XCTAssertNil(IslandEvent.customTitle(""))
        // Spaces alone must not blank the island out.
        XCTAssertNil(IslandEvent.customTitle("   \n "))
        XCTAssertEqual(IslandEvent.farewell(hour: 2, batteryPercent: nil, custom: " ").title, "İyi geceler")
    }

    func testALineTooLongForTheIslandIsCut() {
        let long = String(repeating: "a", count: IslandEvent.customTitleLimit + 20)
        XCTAssertEqual(IslandEvent.customTitle(long)?.count, IslandEvent.customTitleLimit)
    }
}
