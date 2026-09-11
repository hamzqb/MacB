import Foundation

/// One process as the kernel reports it, before anything is grouped or ranked.
public struct ProcessSample: Equatable, Sendable {
    public let pid: Int32
    /// Full path of the executable, when the kernel would give one.
    public let path: String
    /// Process name, used when there is no path to read.
    public let name: String
    public let residentBytes: UInt64
    /// User plus system time since the process started, in nanoseconds.
    public let cpuTimeNanos: UInt64

    public init(pid: Int32, path: String, name: String, residentBytes: UInt64, cpuTimeNanos: UInt64) {
        self.pid = pid
        self.path = path
        self.name = name
        self.residentBytes = residentBytes
        self.cpuTimeNanos = cpuTimeNanos
    }
}

/// What one application is costing, with its helpers folded back into it.
public struct ProcessUsage: Identifiable, Equatable, Sendable {
    public let name: String
    public let memoryBytes: UInt64
    /// Share of one core, so a process using four cores flat reads 400.
    public let cpuPercent: Double
    /// How many processes were added together, helpers included.
    public let processCount: Int
    /// The process that is using the most memory in the group, which is the one
    /// worth naming when the group is asked to stop.
    public let leadPID: Int32
    /// Path of the bundle when the group came from one, so the icon can be read.
    public let bundlePath: String?

    public var id: String { name }

    public init(name: String, memoryBytes: UInt64, cpuPercent: Double,
                processCount: Int, leadPID: Int32, bundlePath: String? = nil) {
        self.name = name
        self.memoryBytes = memoryBytes
        self.cpuPercent = cpuPercent
        self.processCount = processCount
        self.leadPID = leadPID
        self.bundlePath = bundlePath
    }
}

/// Turns raw samples into the short list a person can act on.
///
/// Pure on purpose, like the uninstaller's matcher: the grouping decides what
/// the user is told to quit, so it has to be provable without a kernel.
public enum ProcessRanking {
    /// The bundle an executable belongs to, when it is inside one.
    ///
    /// "/Applications/Google Chrome.app/Contents/Frameworks/.../Google Chrome
    /// Helper (Renderer).app/Contents/MacOS/…" has to come back as Chrome, not
    /// as the innermost helper bundle, so the outermost .app wins.
    public static func bundlePath(forExecutablePath path: String) -> String? {
        guard !path.isEmpty else { return nil }
        var components: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            components.append(String(component))
            if component.hasSuffix(".app") {
                return "/" + components.joined(separator: "/")
            }
        }
        return nil
    }

    /// What to call a sample before any display name is looked up.
    public static func groupKey(forExecutablePath path: String, name: String) -> String {
        if let bundle = bundlePath(forExecutablePath: path) {
            let last = bundle.split(separator: "/").last.map(String.init) ?? bundle
            return String(last.dropLast(4))
        }
        // A daemon path still reads better than the truncated name the kernel
        // hands out, which stops at sixteen characters.
        if let last = path.split(separator: "/").last, !last.isEmpty { return String(last) }
        return name
    }

    /// Folds helpers into their application and works out what each one costs.
    ///
    /// CPU is a rate, so it needs two readings. A process that appears for the
    /// first time contributes memory and no CPU, rather than its whole lifetime
    /// of work reported as if it had happened in the last few seconds.
    public static func usage(current: [ProcessSample], previous: [Int32: UInt64],
                             elapsed: TimeInterval) -> [ProcessUsage] {
        guard elapsed > 0 else { return [] }
        var memory: [String: UInt64] = [:]
        var cpu: [String: Double] = [:]
        var counts: [String: Int] = [:]
        var lead: [String: (pid: Int32, bytes: UInt64)] = [:]
        var bundles: [String: String] = [:]

        for sample in current {
            let key = groupKey(forExecutablePath: sample.path, name: sample.name)
            memory[key, default: 0] += sample.residentBytes
            counts[key, default: 0] += 1
            if let before = previous[sample.pid], sample.cpuTimeNanos >= before {
                let delta = Double(sample.cpuTimeNanos - before)
                cpu[key, default: 0] += delta / (elapsed * 1_000_000_000) * 100
            }
            if sample.residentBytes > (lead[key]?.bytes ?? 0) {
                lead[key] = (sample.pid, sample.residentBytes)
            }
            if bundles[key] == nil, let bundle = bundlePath(forExecutablePath: sample.path) {
                bundles[key] = bundle
            }
        }

        return memory.map { key, bytes in
            ProcessUsage(name: key, memoryBytes: bytes,
                         cpuPercent: (cpu[key] ?? 0).rounded(toPlaces: 1),
                         processCount: counts[key] ?? 1,
                         leadPID: lead[key]?.pid ?? 0,
                         bundlePath: bundles[key])
        }
    }

    /// The heaviest by memory, which is what people mean by "what is eating my RAM".
    public static func topByMemory(_ usage: [ProcessUsage], limit: Int) -> [ProcessUsage] {
        Array(usage.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(max(0, limit)))
    }

    /// The busiest by processor. Ties fall back to memory so the order is stable
    /// rather than reshuffling every refresh when several sit at zero.
    public static func topByCPU(_ usage: [ProcessUsage], limit: Int) -> [ProcessUsage] {
        let sorted = usage.sorted {
            $0.cpuPercent != $1.cpuPercent ? $0.cpuPercent > $1.cpuPercent : $0.memoryBytes > $1.memoryBytes
        }
        return Array(sorted.prefix(max(0, limit)))
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
