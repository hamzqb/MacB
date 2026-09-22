import AppKit
import Combine
import Darwin
import IOKit.ps

struct SystemSnapshot: Equatable {
    var cpuUsage: Double = 0
    var usedMemory: UInt64 = 0
    var totalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    var availableDisk: Int64 = 0
    var totalDisk: Int64 = 0
    var batteryPercent: Double?
    var isCharging = false
    var thermalState: ProcessInfo.ThermalState = .nominal
}

/// A read-only system overview. It intentionally does not access SMC or control fans.
@MainActor final class SystemMonitorService: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()
    /// The last readings, oldest first, for the widget's running line.
    ///
    /// A number tells you the load right now; the line tells you whether it has
    /// been like that all along, which is the question people actually have.
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryHistory: [Double] = []

    /// The stats page's lines, oldest first. GPU is 0…1; the rates are
    /// bytes per second. Sampled every second while that page is open and at
    /// the monitor's slow pace otherwise.
    @Published private(set) var gpuHistory: [Double] = []
    @Published private(set) var networkInHistory: [Double] = []
    @Published private(set) var networkOutHistory: [Double] = []
    @Published private(set) var diskReadHistory: [Double] = []
    @Published private(set) var diskWriteHistory: [Double] = []

    static let historyLength = 32
    static let statsHistoryLength = 48

    private var statsVisible = false
    private var previousCounters: (date: Date, network: (UInt64, UInt64), disk: (UInt64, UInt64))?

    private var timer: Timer?
    private var interval: TimeInterval = 8
    private var previousTicks: (used: UInt64, total: UInt64)?

    func start() {
        guard timer == nil else { return }
        refresh()
        schedule()
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// Samples every couple of seconds while the panel is open and backs off to
    /// every eight when it is not. A line that only moves once a minute is not a
    /// line, and polling that fast with nothing on screen is waste.
    func setFastSampling(_ fast: Bool) {
        let wanted: TimeInterval = statsVisible ? 1 : (fast ? 2 : 8)
        guard wanted != interval else { return }
        interval = wanted
        guard timer != nil else { return }
        schedule()
    }

    /// The stats page draws lines a second apart; everything else can wait.
    func setStatsVisible(_ visible: Bool) {
        guard visible != statsVisible else { return }
        statsVisible = visible
        interval = visible ? 1 : 2
        if timer != nil { schedule() }
        if visible { refresh() }
    }

    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = interval / 5
    }

    func refresh() {
        let ticks = Self.cpuTicks()
        var next = Self.readSnapshot()
        if let old = previousTicks, ticks.used >= old.used, ticks.total >= old.total {
            let usedDelta = ticks.used - old.used
            let totalDelta = ticks.total - old.total
            next.cpuUsage = totalDelta == 0 ? 0 : min(100, Double(usedDelta) / Double(totalDelta) * 100)
        }
        previousTicks = ticks
        snapshot = next
        append(&cpuHistory, next.cpuUsage / 100)
        append(&memoryHistory, next.totalMemory == 0 ? 0 : Double(next.usedMemory) / Double(next.totalMemory))
        // Cheap reads (a sysctl and two registry walks), taken at whatever
        // pace the monitor runs, so the stats page opens onto a full line.
        sampleCounters()
    }

    private func sampleCounters() {
        if let gpu = SystemCounters.gpuUtilization() { appendStat(&gpuHistory, gpu) }
        let now = Date()
        let network = SystemCounters.networkBytes()
        let disk = SystemCounters.diskBytes()
        defer { previousCounters = (now, (network.received, network.sent), (disk.read, disk.written)) }
        guard let old = previousCounters else { return }
        let seconds = max(0.2, now.timeIntervalSince(old.date))
        func rate(_ new: UInt64, _ previous: UInt64) -> Double {
            new >= previous ? Double(new - previous) / seconds : 0
        }
        appendStat(&networkInHistory, rate(network.received, old.network.0))
        appendStat(&networkOutHistory, rate(network.sent, old.network.1))
        appendStat(&diskReadHistory, rate(disk.read, old.disk.0))
        appendStat(&diskWriteHistory, rate(disk.written, old.disk.1))
    }

    private func appendStat(_ series: inout [Double], _ value: Double) {
        series.append(max(0, value))
        if series.count > Self.statsHistoryLength { series.removeFirst(series.count - Self.statsHistoryLength) }
    }

    private func append(_ series: inout [Double], _ value: Double) {
        series.append(min(1, max(0, value)))
        if series.count > Self.historyLength { series.removeFirst(series.count - Self.historyLength) }
    }

    private nonisolated static func cpuTicks() -> (used: UInt64, total: UInt64) {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    private nonisolated static func readSnapshot() -> SystemSnapshot {
        var result = SystemSnapshot()
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        var vm = vm_statistics64()
        let status = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if status == KERN_SUCCESS {
            let active = UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
            result.usedMemory = min(result.totalMemory, active * UInt64(pageSize))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            result.availableDisk = values.volumeAvailableCapacityForImportantUsage ?? 0
            result.totalDisk = Int64(values.volumeTotalCapacity ?? 0)
        }
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
           let source = sources.first,
           let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] {
            if let current = description[kIOPSCurrentCapacityKey] as? Double,
               let maximum = description[kIOPSMaxCapacityKey] as? Double, maximum > 0 {
                result.batteryPercent = current / maximum * 100
            }
            result.isCharging = (description[kIOPSIsChargingKey] as? Bool) == true
        }
        result.thermalState = ProcessInfo.processInfo.thermalState
        return result
    }
}
