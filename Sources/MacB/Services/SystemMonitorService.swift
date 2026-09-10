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
    private var timer: Timer?
    private var previousTicks: (used: UInt64, total: UInt64)?

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 1.5
    }

    func stop() { timer?.invalidate(); timer = nil }

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
