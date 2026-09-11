import XCTest
@testable import MacBCore

final class WindowDesktopTests: XCTestCase {
    func testRealSpaceAssignmentUsesMissionControlOrder() {
        let current = WindowDesktopAssignment.resolve(spaceIDs: [3], orderedSpaceIDs: [3, 4], currentSpaceIDs: [3])
        let second = WindowDesktopAssignment.resolve(spaceIDs: [4], orderedSpaceIDs: [3, 4], currentSpaceIDs: [3])
        XCTAssertEqual(current, .init(location: .current, index: 1))
        XCTAssertEqual(second, .init(location: .other, index: 2))
    }

    func testStickyWindowBelongsToCurrentDesktop() {
        XCTAssertEqual(WindowDesktopAssignment.resolve(spaceIDs: [4, 3], orderedSpaceIDs: [3, 4], currentSpaceIDs: [3]),
                       .init(location: .current, index: 1))
    }

    func testMissingMembershipRemainsUnknown() {
        XCTAssertEqual(WindowDesktopAssignment.resolve(spaceIDs: [], orderedSpaceIDs: [3, 4], currentSpaceIDs: [3]),
                       .init(location: .unknown, index: nil))
    }

    func testVisibleWindowBelongsToCurrentDesktop() {
        XCTAssertEqual(WindowDesktopClassifier.classify(isOnScreen: true,
                                                        isMinimized: false, isApplicationHidden: false), .current)
    }

    func testInactiveOffscreenWindowBelongsToAnotherDesktop() {
        XCTAssertEqual(WindowDesktopClassifier.classify(isOnScreen: false,
                                                        isMinimized: false, isApplicationHidden: false), .other)
    }

    func testUncertainStatesAreNotMislabeledAsAnotherDesktop() {
        XCTAssertEqual(WindowDesktopClassifier.classify(isOnScreen: nil,
                                                        isMinimized: false, isApplicationHidden: false), .unknown)
        XCTAssertEqual(WindowDesktopClassifier.classify(isOnScreen: false,
                                                        isMinimized: true, isApplicationHidden: false), .unknown)
        XCTAssertEqual(WindowDesktopClassifier.classify(isOnScreen: false,
                                                        isMinimized: false, isApplicationHidden: true), .unknown)
    }
}
