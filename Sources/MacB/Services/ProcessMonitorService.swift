import AppKit
import Combine
import Darwin
import MacBCore

/// Reads what every process is costing, and can ask one to quit.
///
/// Read-only apart from the quit, and the quit is the polite one: a terminate
/// request an editor with unsaved work is free to refuse. Nothing is killed.
@MainActor final class ProcessMonitorService: ObservableObject {
    @Published private(set) var byMemory: [ProcessUsage] = []
    @Published private(set) var byCPU: [ProcessUsage] = []
    /// How much of the listed memory the top entries account for, so the widget
    /// can say something true when nothing is unusually large.
    @Published private(set) var lastUpdate = Date.distantPast

    private var timer: Timer?
    private var previousCPU: [Int32: UInt64] = [:]
    private var previousSampleDate: Date?
    private var isSampling = false

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 1.5
    }

    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        guard !isSampling else { return }
        isSampling = true
        let previous = previousCPU
        let elapsed = previousSampleDate.map { Date().timeIntervalSince($0) } ?? 0
        Task.detached(priority: .utility) {
            let samples = Self.sample()
            let usage = elapsed > 0
                ? ProcessRanking.usage(current: samples, previous: previous, elapsed: elapsed)
                : ProcessRanking.usage(current: samples, previous: [:], elapsed: 1)
            let times = Dictionary(samples.map { ($0.pid, $0.cpuTimeNanos) }, uniquingKeysWith: { first, _ in first })
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.byMemory = ProcessRanking.topByMemory(usage, limit: 8)
                self.byCPU = ProcessRanking.topByCPU(usage, limit: 8)
                self.previousCPU = times
                self.previousSampleDate = Date()
                self.lastUpdate = Date()
                self.isSampling = false
            }
        }
    }

    /// Asks the application behind a group to quit.
    ///
    /// Only a real application is ever asked. A daemon has nobody to object on
    /// its behalf, and stopping one is the system's business, not MacB's.
    @discardableResult
    func quit(_ usage: ProcessUsage) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: usage.leadPID),
              application.activationPolicy != .prohibited,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
        return application.terminate()
    }

    func canQuit(_ usage: ProcessUsage) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: usage.leadPID) else { return false }
        return application.activationPolicy != .prohibited
            && application.bundleIdentifier != Bundle.main.bundleIdentifier
    }

    func icon(for usage: ProcessUsage) -> NSImage? {
        guard let path = usage.bundlePath else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }

    // MARK: - Sampling

    private nonisolated static func sample() -> [ProcessSample] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let written = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard written > 0 else { return [] }

        var samples: [ProcessSample] = []
        samples.reserveCapacity(Int(written))
        for index in 0..<Int(written) {
            let pid = pids[index]
            guard pid > 0 else { continue }
            var info = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            // A process owned by somebody else, or one that exited between the
            // listing and the read, simply is not ours to report.
            guard result == 0 else { continue }
            let resident = info.ri_resident_size
            guard resident > 0 else { continue }
            samples.append(ProcessSample(pid: pid,
                                         path: path(of: pid),
                                         name: name(of: pid),
                                         residentBytes: resident,
                                         cpuTimeNanos: info.ri_user_time + info.ri_system_time))
        }
        return samples
    }

    private nonisolated static func path(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(cString: buffer)
    }

    private nonisolated static func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "\(pid)" }
        return String(cString: buffer)
    }
}
