import XCTest
@testable import MacBCore

final class PanelStateTests: XCTestCase {
    func testHoverWaits180MillisecondsAndOpensOnlyGlance() {
        var state = PanelState()
        state.pointerEntered(at: 0)
        state.pointerEntered(at: 0.1)
        state.tick(at: 0.179)
        XCTAssertEqual(state.phase, .collapsed)
        state.tick(at: 0.18)
        XCTAssertEqual(state.phase, .glance)
        XCTAssertEqual(state.content, .music)
        state.tick(at: 10)
        XCTAssertEqual(state.phase, .glance)
    }

    func testRapidExitCancelsHoverAndReentryStartsFreshDelay() {
        var state = PanelState()
        state.pointerEntered(at: 0)
        state.pointerExited(at: 0.1)
        state.tick(at: 0.2)
        XCTAssertEqual(state.phase, .collapsed)
        state.pointerEntered(at: 0.25)
        state.tick(at: 0.42)
        XCTAssertEqual(state.phase, .collapsed)
        state.tick(at: 0.44)
        XCTAssertEqual(state.phase, .glance)
        state.pointerExited(at: 1)
        state.tick(at: 1.29)
        XCTAssertEqual(state.phase, .glance)
        state.tick(at: 1.31)
        XCTAssertEqual(state.phase, .collapsed)
    }

    func testClickExpandsImmediatelyAndHoverCannotDowngradeIt() {
        var state = PanelState()
        state.pointerEntered(at: 0)
        state.open()
        state.tick(at: 1)
        XCTAssertEqual(state.phase, .expanded)
        XCTAssertNil(state.hoverDeadline)
        state.select(.files)
        state.glance()
        XCTAssertEqual(state.phase, .expanded)
        XCTAssertEqual(state.content, .files)
    }

    func testDragOpensFilesDirectlyAndCloseResetsAllState() {
        var state = PanelState()
        state.pointerEntered(at: 0)
        state.setDragging(true)
        XCTAssertEqual(state.phase, .expanded)
        XCTAssertEqual(state.content, .files)
        XCTAssertNil(state.hoverDeadline)
        state.setKeyboardFocus(true)
        state.pointerExited(at: 0.1)
        state.tick(at: 10)
        XCTAssertEqual(state.phase, .expanded)
        state.close()
        XCTAssertEqual(state, PanelState())
        state.tick(at: 20)
        XCTAssertEqual(state.phase, .collapsed)
    }

    func testPointerCrossingCancelsDelayedClose() {
        var state = PanelState()
        state.open()
        state.pointerExited(at: 0)
        state.tick(at: 0.2)
        XCTAssertTrue(state.isOpen)
        state.pointerEntered()
        state.tick(at: 1)
        XCTAssertTrue(state.isOpen)
    }
    func testDragAndFocusPreventClosingUntilReleased() {
        var state = PanelState()
        state.setDragging(true)
        state.pointerExited(at: 0)
        state.tick(at: 1)
        XCTAssertTrue(state.isOpen)
        state.setDragging(false)
        state.setKeyboardFocus(true)
        state.pointerExited(at: 1)
        state.tick(at: 2)
        XCTAssertTrue(state.isOpen)
        state.setKeyboardFocus(false)
        state.tick(at: 3)
        XCTAssertFalse(state.isOpen)
    }
    func testEscapeResetsInteraction() {
        var state = PanelState()
        state.setDragging(true)
        state.close()
        XCTAssertEqual(state, PanelState())
    }

    func testCommandsContentClosesBackToDefaultMusicState() {
        var state = PanelState()
        state.select(.commands)
        XCTAssertEqual(state.phase, .expanded)
        XCTAssertEqual(state.content, .commands)
        state.close()
        XCTAssertEqual(state, PanelState())
    }

    func testMorphHasExactEndpointsAndSmallFiniteOvershoot() {
        XCTAssertEqual(MorphTiming.progress(-1), 0)
        XCTAssertEqual(MorphTiming.progress(0), 0)
        XCTAssertEqual(MorphTiming.progress(1), 1)
        XCTAssertEqual(MorphTiming.progress(2), 1)
        var hasOvershoot = false
        for sample in 0...1000 {
            let progress = MorphTiming.progress(Double(sample) / 1000)
            XCTAssertTrue(progress.isFinite)
            XCTAssertGreaterThanOrEqual(progress, 0)
            XCTAssertLessThanOrEqual(progress, 1.1)
            hasOvershoot = hasOvershoot || progress > 1
        }
        XCTAssertTrue(hasOvershoot)
    }

    func testInterruptedMorphRebasesWithoutJumpAndSettlesExactly() {
        for fraction in [0.05, 0.2, 0.5, 0.9] {
            let currentWidth = 220 + (440 - 220) * MorphTiming.progress(fraction)
            let rebasedStart = currentWidth + (220 - currentWidth) * MorphTiming.progress(0)
            let rebasedEnd = currentWidth + (220 - currentWidth) * MorphTiming.progress(1)
            XCTAssertEqual(rebasedStart, currentWidth, accuracy: 0.000001)
            XCTAssertEqual(rebasedEnd, 220, accuracy: 0.000001)
        }
    }
}
