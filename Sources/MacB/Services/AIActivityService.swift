import AppKit
import Combine

enum AIAssistantKind: String, Codable, CaseIterable {
    case claude = "Claude"
    case codex = "Codex"
    case chatGPT = "ChatGPT"
    case cursor = "Cursor"
    case copilot = "Copilot"
    case gemini = "Gemini"
    case windsurf = "Windsurf"

    var symbol: String {
        switch self {
        case .claude: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .chatGPT: return "bubble.left.and.bubble.right.fill"
        case .cursor: return "cursorarrow.rays"
        case .copilot: return "person.crop.circle.badge.checkmark"
        case .gemini: return "diamond.fill"
        case .windsurf: return "wind"
        }
    }
}

struct AIAssistantUsage: Equatable {
    let kind: AIAssistantKind
    let primaryRemainingPercent: Double?
    let secondaryRemainingPercent: Double?
    let updatedAt: Date

    var remainingPercent: Double? {
        [primaryRemainingPercent, secondaryRemainingPercent].compactMap { $0 }.min()
    }

    var compactText: String? {
        remainingPercent.map { "\(Int($0.rounded()))% kaldı" }
    }
}

struct AIAssistantStatus: Identifiable, Equatable {
    var id: String { kind.rawValue }
    let kind: AIAssistantKind
    let isRunning: Bool
    let source: String?
    let usage: AIAssistantUsage?

    var detail: String {
        if kind == .chatGPT, usage?.kind == .codex, let text = usage?.compactText {
            return "Codex \(text)"
        }
        return usage?.compactText ?? (isRunning ? "çalışıyor" : "hazır")
    }
}

struct AIActivity: Identifiable, Equatable {
    let id: String
    let kind: AIAssistantKind
    let processID: Int32
    let source: String
    let command: String
    let elapsed: TimeInterval

    var elapsedText: String {
        let seconds = max(0, Int(elapsed))
        if seconds < 60 { return "\(seconds) sn" }
        if seconds < 3_600 { return "\(seconds / 60) dk" }
        return "\(seconds / 3_600) sa \((seconds % 3_600) / 60) dk"
    }
}

private struct DesktopAssistant: Sendable {
    let processID: Int32
    let kind: AIAssistantKind
    let isActive: Bool
}

/// Detects Claude and Codex desktop/terminal processes without reading prompts or terminal contents.
@MainActor final class AIActivityService: ObservableObject {
    @Published private(set) var activities: [AIActivity] = []
    @Published private(set) var usages: [AIAssistantUsage] = []
    @Published private(set) var lastUpdated: Date?
    private var timer: Timer?
    private var refreshInProgress = false
    private var lastUsageRefresh = Date.distantPast

    var isActive: Bool { !activities.isEmpty }

    /// One row per provider. Helper processes and multiple terminal sessions do
    /// not create duplicate Codex or Claude badges.
    var statuses: [AIAssistantStatus] {
        let running = Dictionary(grouping: activities, by: \AIActivity.kind)
        let usageByKind = Dictionary(uniqueKeysWithValues: usages.map { ($0.kind, $0) })
        return AIAssistantKind.allCases.compactMap { kind in
            let processes = running[kind] ?? []
            // A saved allowance is not evidence that an application is open.
            // It only enriches a provider that the process scan can see now.
            guard !processes.isEmpty else { return nil }
            let usage = usageByKind[kind] ?? (kind == .chatGPT ? usageByKind[.codex] : nil)
            return AIAssistantStatus(kind: kind, isRunning: !processes.isEmpty,
                                     source: processes.first?.source, usage: usage)
        }
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 2
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        activities = []
    }

    func refresh() {
        guard !refreshInProgress else { return }
        refreshInProgress = true
        let desktopApps = NSWorkspace.shared.runningApplications.compactMap { application -> DesktopAssistant? in
            guard application.activationPolicy == .regular, !application.isTerminated else { return nil }
            guard let kind = Self.kind(bundleIdentifier: application.bundleIdentifier,
                                       name: application.localizedName) else { return nil }
            return DesktopAssistant(processID: application.processIdentifier, kind: kind, isActive: application.isActive)
        }
        let shouldRefreshUsage = Date().timeIntervalSince(lastUsageRefresh) >= 60
        if shouldRefreshUsage { lastUsageRefresh = Date() }
        Task {
            async let processResult = Self.scanProcesses(desktopApps: desktopApps)
            async let usageResult: [AIAssistantUsage]? = shouldRefreshUsage ? Self.scanUsage() : nil
            let result = await processResult
            activities = result
            if let fresh = await usageResult { usages = fresh }
            lastUpdated = Date()
            refreshInProgress = false
        }
    }

    private nonisolated static func scanProcesses(desktopApps: [DesktopAssistant]) async -> [AIActivity] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/bin/ps")
                process.arguments = ["-axo", "pid=,etime=,command="]
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0,
                          let output = String(data: data, encoding: .utf8) else {
                        continuation.resume(returning: [])
                        return
                    }
                    let ownPID = ProcessInfo.processInfo.processIdentifier
                    let desktopByPID = Dictionary(uniqueKeysWithValues: desktopApps.map { ($0.processID, $0) })
                    let items = output.split(separator: "\n").compactMap { line -> AIActivity? in
                        let fields = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 2, whereSeparator: { $0.isWhitespace })
                        guard fields.count == 3, let pid = Int32(fields[0]), pid != ownPID,
                              let elapsed = parseElapsed(String(fields[1])) else { return nil }
                        let command = String(fields[2])
                        let lower = command.lowercased()
                        let kind: AIAssistantKind
                        let source: String
                        if let desktop = desktopByPID[pid] {
                            kind = desktop.kind
                            source = "Uygulama"
                        } else {
                            let firstToken = lower.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
                            let executable = URL(fileURLWithPath: firstToken).lastPathComponent
                            let isEmbeddedHelper = lower.contains("/contents/frameworks/") || lower.contains("/contents/helpers/")
                                || lower.contains("/applications/chatgpt.app/contents/resources/codex ")
                            guard !isEmbeddedHelper,
                                  let detected = Self.kind(executable: executable, command: lower) else { return nil }
                            kind = detected
                            source = "Terminal"
                        }
                        let executable = kind.rawValue.lowercased()
                        return AIActivity(id: "\(kind.rawValue)-\(pid)", kind: kind, processID: pid,
                                          source: source, command: executable, elapsed: elapsed)
                    }
                    let activePIDs = Set(desktopApps.filter(\.isActive).map(\.processID))
                    continuation.resume(returning: items.sorted {
                        if activePIDs.contains($0.processID) != activePIDs.contains($1.processID) {
                            return activePIDs.contains($0.processID)
                        }
                        if ($0.source == "Uygulama") != ($1.source == "Uygulama") { return $0.source == "Uygulama" }
                        if $0.kind != $1.kind { return $0.kind == .codex }
                        return $0.elapsed > $1.elapsed
                    })
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    private nonisolated static func kind(bundleIdentifier: String?, name: String?) -> AIAssistantKind? {
        let bundle = bundleIdentifier?.lowercased() ?? ""
        let appName = name?.lowercased() ?? ""
        if bundle == "com.openai.codex" || appName == "codex" { return .codex }
        if appName == "claude" && bundle.contains("anthropic") { return .claude }
        if appName == "chatgpt" && bundle.contains("openai") { return .chatGPT }
        // macOS itself runs CursorUIViewService. Requiring the foreground app's
        // exact name prevents that system helper from becoming a fake editor.
        if appName == "cursor" && (bundle.contains("todesktop") || bundle.hasPrefix("com.cursor")) { return .cursor }
        if appName.contains("copilot") && bundle.contains("copilot") { return .copilot }
        if appName == "windsurf" && (bundle.contains("windsurf") || bundle.contains("exafunction")) { return .windsurf }
        return nil
    }

    private nonisolated static func kind(executable: String, command: String) -> AIAssistantKind? {
        if executable == "claude" { return .claude }
        if executable == "codex" { return .codex }
        if executable == "gemini" { return .gemini }
        if executable == "github-copilot-cli" || executable == "copilot" { return .copilot }
        if command.contains("windsurf") { return .windsurf }
        return nil
    }

    /// Reads only status events already written by the local clients. It never
    /// opens auth files, cookies or API keys and never sends a request on behalf
    /// of the user. Providers without a machine-readable local status stay nil.
    private nonisolated static func scanUsage() async -> [AIAssistantUsage] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: codexUsage().map { [$0] } ?? [])
            }
        }
    }

    private nonisolated static func codexUsage() -> AIAssistantUsage? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [home.appendingPathComponent(".codex/sessions", isDirectory: true),
                     home.appendingPathComponent(".codex/archived_sessions", isDirectory: true)]
        var candidates: [(URL, Date)] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                if values?.isRegularFile == true { candidates.append((url, values?.contentModificationDate ?? .distantPast)) }
            }
        }
        for (url, modified) in candidates.sorted(by: { $0.1 > $1.1 }).prefix(20) {
            guard let object = lastRateLimitObject(in: url),
                  let payload = object["payload"] as? [String: Any],
                  let limits = payload["rate_limits"] as? [String: Any] else { continue }
            func remaining(_ key: String) -> Double? {
                guard let window = limits[key] as? [String: Any],
                      let used = (window["used_percent"] as? NSNumber)?.doubleValue else { return nil }
                if let reset = (window["resets_at"] as? NSNumber)?.doubleValue,
                   Date(timeIntervalSince1970: reset) <= Date() { return 100 }
                return min(100, max(0, 100 - used))
            }
            return AIAssistantUsage(kind: .codex, primaryRemainingPercent: remaining("primary"),
                                    secondaryRemainingPercent: remaining("secondary"), updatedAt: modified)
        }
        return nil
    }

    private nonisolated static func lastRateLimitObject(in url: URL) -> [String: Any]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        let length = min(UInt64(512 * 1024), end)
        try? handle.seek(toOffset: end - length)
        guard let data = try? handle.read(upToCount: Int(length)),
              let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            return object
        }
        return nil
    }

    private nonisolated static func parseElapsed(_ value: String) -> TimeInterval? {
        let dayParts = value.split(separator: "-", maxSplits: 1).map(String.init)
        let days: Int
        let clock: String
        if dayParts.count == 2 { days = Int(dayParts[0]) ?? 0; clock = dayParts[1] }
        else { days = 0; clock = dayParts[0] }
        let units = clock.split(separator: ":").compactMap { Int($0) }
        guard units.count == 2 || units.count == 3 else { return nil }
        let hours = units.count == 3 ? units[0] : 0
        let minutes = units.count == 3 ? units[1] : units[0]
        let seconds = units.last ?? 0
        return TimeInterval(days * 86_400 + hours * 3_600 + minutes * 60 + seconds)
    }
}
