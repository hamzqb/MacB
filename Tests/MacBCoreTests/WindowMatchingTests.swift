import XCTest
import CoreGraphics
@testable import MacBCore

final class WindowMatchingTests: XCTestCase {
    let frame = CGRect(x: 20, y: 40, width: 800, height: 600)
    func candidate(_ id: UInt32, pid: Int32 = 10, title: String = "Document", frame: CGRect? = nil) -> WindowDescriptor {
        .init(id: id, pid: pid, title: title, frame: frame ?? self.frame)
    }
    func testRequiresSameProcessAndGeometry() {
        XCTAssertEqual(WindowMatcher.uniqueMatch(pid: 10, title: "Document", frame: frame, candidates: [candidate(1, pid: 20), candidate(2)]), 2)
        XCTAssertNil(WindowMatcher.uniqueMatch(pid: 10, title: "Document", frame: frame, candidates: [candidate(1, frame: frame.offsetBy(dx: 50, dy: 0))]))
    }
    func testEqualTitlesUseGeometryAndAmbiguityReturnsNil() {
        XCTAssertEqual(WindowMatcher.uniqueMatch(pid: 10, title: "Document", frame: frame, candidates: [candidate(1), candidate(2, frame: frame.offsetBy(dx: 100, dy: 0))]), 1)
        XCTAssertNil(WindowMatcher.uniqueMatch(pid: 10, title: "Document", frame: frame, candidates: [candidate(1), candidate(2)]))
    }
    func testMissingTitleStillRequiresUnambiguousGeometry() {
        XCTAssertEqual(WindowMatcher.uniqueMatch(pid: 10, title: "Document", frame: frame, candidates: [candidate(1, title: "")]), 1)
        XCTAssertNil(WindowMatcher.uniqueMatch(pid: 10, title: "", frame: frame, candidates: [candidate(1), candidate(2)]))
        XCTAssertNil(WindowMatcher.uniqueMatch(pid: 10, title: "Document", frame: .zero, candidates: [candidate(1)]))
    }
    func testDifferentNonemptyTitlesNeverMatch() {
        XCTAssertNil(WindowMatcher.uniqueMatch(pid: 10, title: "Private", frame: frame, candidates: [candidate(1)]))
    }
}
