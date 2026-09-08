import XCTest
@testable import MacBCore

final class WindowSelectionTests: XCTestCase {
    func testCycleAndReverseWrap() {
        var selection = WindowSelection()
        selection.replace(with: ["a", "b", "c"])
        selection.advance(backwards: true)
        XCTAssertEqual(selection.selectedID, "c")
        selection.advance()
        XCTAssertEqual(selection.selectedID, "a")
    }
    func testLiveRefreshPreservesSelectionAndClosedWindowFallsBack() {
        var selection = WindowSelection()
        selection.replace(with: ["a", "b", "c"])
        selection.select("b")
        selection.replace(with: ["c", "b", "a"])
        XCTAssertEqual(selection.selectedID, "b")
        selection.replace(with: ["c", "a"])
        XCTAssertEqual(selection.selectedID, "a")
        selection.replace(with: [])
        XCTAssertNil(selection.selectedID)
        selection.advance()
        XCTAssertNil(selection.selectedID)
    }
}
