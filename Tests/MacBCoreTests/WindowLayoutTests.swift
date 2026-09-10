import CoreGraphics
import XCTest
@testable import MacBCore

final class WindowLayoutTests: XCTestCase {
    private let area = CGRect(x: 100, y: 40, width: 1200, height: 800)

    func testHalvesAndCornersCoverVisibleAreaWithoutOverlap() throws {
        let current = CGRect(x: 200, y: 100, width: 640, height: 480)
        let left = try XCTUnwrap(WindowLayout.frame(for: .leftHalf, in: area, current: current))
        let right = try XCTUnwrap(WindowLayout.frame(for: .rightHalf, in: area, current: current))
        XCTAssertEqual(left.union(right), area)
        XCTAssertEqual(left.intersection(right).width, 0)
        XCTAssertEqual(try XCTUnwrap(WindowLayout.frame(for: .topLeft, in: area, current: current)),
                       CGRect(x: 100, y: 40, width: 600, height: 400))
        XCTAssertEqual(try XCTUnwrap(WindowLayout.frame(for: .bottomRight, in: area, current: current)),
                       CGRect(x: 700, y: 440, width: 600, height: 400))
    }

    func testCenterKeepsSizeAndClampsOversizedWindow() throws {
        XCTAssertEqual(try XCTUnwrap(WindowLayout.frame(for: .center, in: area,
                                                        current: CGRect(x: 0, y: 0, width: 600, height: 400))),
                       CGRect(x: 400, y: 240, width: 600, height: 400))
        XCTAssertEqual(try XCTUnwrap(WindowLayout.frame(for: .center, in: area,
                                                        current: CGRect(x: 0, y: 0, width: 2000, height: 1000))), area)
    }

    func testMovingDisplayPreservesRelativeSizeAndPosition() throws {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let target = CGRect(x: 1000, y: 0, width: 2000, height: 1200)
        let current = CGRect(x: 250, y: 200, width: 500, height: 400)
        XCTAssertEqual(try XCTUnwrap(WindowLayout.frameOnNextDisplay(current: current, from: source, to: target)),
                       CGRect(x: 1500, y: 300, width: 1000, height: 600))
    }
}
