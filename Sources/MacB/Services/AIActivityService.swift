import AppKit
import Combine

enum AIAssistantKind: String, Codable, CaseIterable {
    case claude = "Claude"
    case codex = "Codex"

    var symbol: String { self == .claude ? "sparkles" : "chevron.left.forwardslash.chevron.right" }
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
    @Published private(set) var lastUpdated: Date?
    private var timer: Timer?
    private var refreshInProgress = false

    var isActive: Bool { !activities.isEmpty }

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
            let kind: AIAssistantKind
            switch application.bundleIdentifier {
            case "com.openai.codex": kind = .codex
            case "com.anthropic.claudefordesktop": kind = .claude
            default: return nil
            }
            return DesktopAssistant(processID: application.processIdentifier, kind: kind, isActive: application.isActive)
        }
        Task {
            let result = await Self.scanProcesses(desktopApps: desktopApps)
            activities = result
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
                            if executable == "claude" && !isEmbeddedHelper { kind = .claude }
                            else if executable == "codex" && !isEmbeddedHelper { kind = .codex }
                            else { return nil }
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
