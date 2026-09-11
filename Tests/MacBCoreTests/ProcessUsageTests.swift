import XCTest
@testable import MacBCore

final class ProcessUsageTests: XCTestCase {
    private let chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    private let helperPath = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"

    func testAHelperIsCreditedToTheApplicationItBelongsTo() {
        XCTAssertEqual(ProcessRanking.bundlePath(forExecutablePath: helperPath),
                       "/Applications/Google Chrome.app")
        XCTAssertEqual(ProcessRanking.groupKey(forExecutablePath: helperPath, name: "Google Chrome H"),
                       "Google Chrome")
        XCTAssertEqual(ProcessRanking.groupKey(forExecutablePath: chromePath, name: "Google Chrome"),
                       "Google Chrome")
    }

    func testADaemonKeepsItsOwnNameRatherThanTheTruncatedOne() {
        XCTAssertNil(ProcessRanking.bundlePath(forExecutablePath: "/usr/libexec/fileproviderd"))
        XCTAssertEqual(ProcessRanking.groupKey(forExecutablePath: "/usr/libexec/fileproviderd", name: "fileproviderd"),
                       "fileproviderd")
        // The kernel truncates the name at sixteen characters; the path does not.
        XCTAssertEqual(ProcessRanking.groupKey(forExecutablePath: "/usr/libexec/com.apple.someverylongdaemon",
                                               name: "com.apple.somev"),
                       "com.apple.someverylongdaemon")
        XCTAssertEqual(ProcessRanking.groupKey(forExecutablePath: "", name: "kernel_task"), "kernel_task")
    }

    func testMemoryIsSummedAndCPUIsARateOverTheGapBetweenReadings() {
        let samples = [
            ProcessSample(pid: 1, path: chromePath, name: "Google Chrome",
                          residentBytes: 400_000_000, cpuTimeNanos: 3_000_000_000),
            ProcessSample(pid: 2, path: helperPath, name: "Google Chrome H",
                          residentBytes: 600_000_000, cpuTimeNanos: 2_000_000_000)
        ]
        let previous: [Int32: UInt64] = [1: 2_000_000_000, 2: 2_000_000_000]
        let usage = ProcessRanking.usage(current: samples, previous: previous, elapsed: 2)
        XCTAssertEqual(usage.count, 1)
        let chrome = try! XCTUnwrap(usage.first)
        XCTAssertEqual(chrome.name, "Google Chrome")
        XCTAssertEqual(chrome.memoryBytes, 1_000_000_000)
        XCTAssertEqual(chrome.processCount, 2)
        // One second of processor time over a two second gap is half a core.
        XCTAssertEqual(chrome.cpuPercent, 50, accuracy: 0.01)
        // The heaviest process is the one named when the group is asked to stop.
        XCTAssertEqual(chrome.leadPID, 2)
        XCTAssertEqual(chrome.bundlePath, "/Applications/Google Chrome.app")
    }

    func testAProcessSeenForTheFirstTimeReportsNoProcessorTime() {
        let samples = [ProcessSample(pid: 9, path: chromePath, name: "Google Chrome",
                                     residentBytes: 100, cpuTimeNanos: 900_000_000_000)]
        let usage = ProcessRanking.usage(current: samples, previous: [:], elapsed: 2)
        // Its whole lifetime of work must not be reported as the last two seconds.
        XCTAssertEqual(usage.first?.cpuPercent, 0)
    }

    func testTheTwoOrderingsAnswerTwoDifferentQuestions() {
        let hungry = ProcessUsage(name: "Hungry", memoryBytes: 900, cpuPercent: 1, processCount: 1, leadPID: 1)
        let busy = ProcessUsage(name: "Busy", memoryBytes: 100, cpuPercent: 90, processCount: 1, leadPID: 2)
        XCTAssertEqual(ProcessRanking.topByMemory([busy, hungry], limit: 2).first?.name, "Hungry")
        XCTAssertEqual(ProcessRanking.topByCPU([hungry, busy], limit: 2).first?.name, "Busy")
        XCTAssertEqual(ProcessRanking.topByMemory([busy, hungry], limit: 1).count, 1)
        XCTAssertTrue(ProcessRanking.topByCPU([busy, hungry], limit: 0).isEmpty)
    }
}
