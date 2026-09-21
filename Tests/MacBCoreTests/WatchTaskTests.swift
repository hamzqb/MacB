import XCTest
@testable import MacBCore

final class WatchTaskTests: XCTestCase {
    func testPriceExtractorReadsCommonFormats() {
        XCTAssertEqual(PriceExtractor.firstPrice(in: "Bugün ₺1.299,90"), 1299.9, accuracy: 0.001)
        XCTAssertEqual(PriceExtractor.firstPrice(in: "$1,299.90 now"), 1299.9, accuracy: 0.001)
        XCTAssertEqual(PriceExtractor.firstPrice(in: "1.299 TL"), 1299, accuracy: 0.001)
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
