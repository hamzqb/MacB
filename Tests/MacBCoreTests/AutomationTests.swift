import XCTest
@testable import MacBCore

final class AutomationTests: XCTestCase {
    private func rule(_ trigger: AutomationTrigger,
                      _ action: AutomationAction = .pauseMedia,
                      enabled: Bool = true) -> AutomationRule {
        AutomationRule(title: "Kural", isEnabled: enabled, trigger: trigger, action: action)
    }

    func testAnEventRunsOnlyTheRulesWaitingForIt() {
        var engine = AutomationEngine(rules: [
            rule(.lidOpened, .showNotice("merhaba")),
            rule(.lidClosing, .pauseMedia)
        ])
        XCTAssertEqual(engine.actions(for: .lidOpened), [.showNotice("merhaba")])
        XCTAssertEqual(engine.actions(for: .lidClosing), [.pauseMedia])
        XCTAssertTrue(engine.actions(for: .timerFinished).isEmpty)
    }

    func testASwitchedOffRuleDoesNothing() {
        var engine = AutomationEngine(rules: [rule(.timerFinished, enabled: false)])
        XCTAssertTrue(engine.actions(for: .timerFinished).isEmpty)
    }

    func testARuleRestsBeforeItCanRunAgain() {
        var engine = AutomationEngine(rules: [rule(.mediaStarted)])
        let start = Date()
        XCTAssertEqual(engine.actions(for: .mediaStarted, now: start).count, 1)
        // Skipping through an album must not open something on every track.
        XCTAssertTrue(engine.actions(for: .mediaStarted, now: start.addingTimeInterval(5)).isEmpty)
        XCTAssertEqual(engine.actions(for: .mediaStarted,
                                      now: start.addingTimeInterval(AutomationEngine.cooldown + 1)).count, 1)
    }

    func testABatteryRuleFiresOnceOnTheWayDown() {
        var engine = AutomationEngine(rules: [rule(.batteryBelow(percent: 20))])
        let start = Date()
        // Already low when MacB started: nothing fires, because nobody watched
        // it cross the line and the Mac has been like this for a while.
        XCTAssertTrue(engine.actions(for: .batteryLevel(15), now: start).isEmpty)
        // Charged back above the line, then drained past it.
        XCTAssertTrue(engine.actions(for: .batteryLevel(60), now: start).isEmpty)
        XCTAssertEqual(engine.actions(for: .batteryLevel(19),
                                      now: start.addingTimeInterval(600)).count, 1)
        // Every further reading on the way to empty is the same crossing.
        XCTAssertTrue(engine.actions(for: .batteryLevel(12),
                                     now: start.addingTimeInterval(1200)).isEmpty)
    }

    func testAnApplicationRuleIgnoresTheCaseOfTheIdentifier() {
        var engine = AutomationEngine(rules: [rule(.appLaunched(bundleIdentifier: "com.spotify.client"))])
        XCTAssertEqual(engine.actions(for: .appLaunched("com.Spotify.Client")).count, 1)
        var other = AutomationEngine(rules: [rule(.appQuit(bundleIdentifier: "com.spotify.client"))])
        XCTAssertTrue(other.actions(for: .appLaunched("com.spotify.client")).isEmpty)
    }

    func testOnlyTheWebAndLocalFilesMayBeOpened() {
        XCTAssertTrue(AutomationAction.openLink("https://example.com").isSafe)
        XCTAssertTrue(AutomationAction.openLink("file:///Users/x/notes.txt").isSafe)
        XCTAssertFalse(AutomationAction.openLink("x-apple-shortcut://run?name=wipe").isSafe)
        XCTAssertFalse(AutomationAction.openLink("javascript:alert(1)").isSafe)
        XCTAssertFalse(AutomationAction.openLink("https://").isSafe)
        XCTAssertFalse(AutomationAction.openLink("   ").isSafe)
    }

    func testAShortcutNameCannotCarryASecondCommand() {
        XCTAssertTrue(AutomationAction.runShortcut(name: "Gece Modu").isSafe)
        XCTAssertFalse(AutomationAction.runShortcut(name: "Gece\nrm -rf /").isSafe)
        XCTAssertFalse(AutomationAction.runShortcut(name: "").isSafe)
    }

    func testAnUnsafeActionNeverRuns() {
        var engine = AutomationEngine(rules: [rule(.lidOpened, .openLink("javascript:alert(1)"))])
        XCTAssertTrue(engine.actions(for: .lidOpened).isEmpty)
        XCTAssertTrue(AutomationAction.startTimer(minutes: 0).isSafe == false)
        XCTAssertTrue(AutomationAction.startTimer(minutes: 25).isSafe)
        XCTAssertFalse(AutomationAction.showNotice("   ").isSafe)
    }

    func testRulesSurviveARestart() throws {
        let rules = [rule(.chargerConnected, .startTimer(minutes: 25)),
                     rule(.appQuit(bundleIdentifier: "com.apple.Safari"), .runShortcut(name: "Kapat"))]
        let data = try JSONEncoder().encode(rules)
        XCTAssertEqual(try JSONDecoder().decode([AutomationRule].self, from: data), rules)
    }

    func testReplacingTheRulesForgetsWhatTheOldOnesDid() {
        let repeated = rule(.lidOpened)
        var engine = AutomationEngine(rules: [repeated])
        let start = Date()
        XCTAssertEqual(engine.actions(for: .lidOpened, now: start).count, 1)
        // A rule that was edited is a new rule, and should not still be resting.
        engine.setRules([rule(.lidOpened)])
        XCTAssertEqual(engine.actions(for: .lidOpened, now: start).count, 1)
    }
}
