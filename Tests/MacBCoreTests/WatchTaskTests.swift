import XCTest
@testable import MacBCore

final class WatchTaskTests: XCTestCase {
    func testPriceExtractorReadsCommonFormats() throws {
        // Unwrapped rather than compared as an optional: `XCTAssertEqual` with
        // an accuracy takes a value, not a maybe, and a price that was not
        // found at all should say so rather than fail as "not close enough".
        for (text, expected) in [("Bugün ₺1.299,90", 1299.9), ("$1,299.90 now", 1299.9), ("1.299 TL", 1299)] {
            let price = try XCTUnwrap(PriceExtractor.firstPrice(in: text), "No price found in “\(text)”")
            XCTAssertEqual(price, expected, accuracy: 0.001, "Wrong price read from “\(text)”")
        }
    }

    func testTextChangedUsesBaseline() {
        let task = WatchTask(title: "Site", kind: .websiteText, target: "https://example.com", condition: .textChanged)
        let first = WatchEvaluation.evaluate(task: task, reading: WatchReading(displayValue: "A", rawValue: " A\n"))
        XCTAssertFalse(first.triggered)
        XCTAssertEqual(first.baseline, "A")
        var nextTask = task
        nextTask.baseline = first.baseline
        XCTAssertTrue(WatchEvaluation.evaluate(task: nextTask, reading: WatchReading(displayValue: "B", rawValue: "B")).triggered)
    }

    func testMetricThresholdsTrigger() {
        let task = WatchTask(title: "CPU", kind: .systemMetric, target: "cpu", condition: .metricAbove(.cpuPercent, 80))
        let reading = WatchReading(displayValue: "91%", numericValue: 91, rawValue: "91")
        XCTAssertTrue(WatchEvaluation.evaluate(task: task, reading: reading).triggered)
    }
}
