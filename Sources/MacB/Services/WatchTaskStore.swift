import AppKit
import Combine
import Foundation
import MacBCore

@MainActor final class WatchTaskStore: ObservableObject {
    @Published private(set) var tasks: [WatchTask] = []
    @Published private(set) var isChecking = false
    @Published var errorMessage: String?

    private let fileURL: URL
    private let systemMonitor: SystemMonitorService
    private let processes: ProcessMonitorService
    private let notify: (String, String) -> Void
    private var timer: Timer?
    private var checkingIDs = Set<UUID>()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(fileURL: URL? = nil, systemMonitor: SystemMonitorService, processes: ProcessMonitorService,
         notify: @escaping (String, String) -> Void) {
        self.systemMonitor = systemMonitor
        self.processes = processes
        self.notify = notify
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacB", isDirectory: true)
            .appendingPathComponent("watchers.json")
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    var activeCount: Int { tasks.filter(\.isEnabled).count }
    var triggeredCount: Int { tasks.filter { $0.status == .triggered }.count }
    var latest: WatchTask? {
        tasks.sorted {
            ($0.lastTriggeredAt ?? $0.lastCheckedAt ?? $0.createdAt) > ($1.lastTriggeredAt ?? $1.lastCheckedAt ?? $1.createdAt)
        }.first
    }

    func start() {
        guard timer == nil else { return }
        schedule()
        Task { await checkDue() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func add(_ task: WatchTask) {
        tasks.insert(task, at: 0)
        save()
        Task { await check(id: task.id, force: true) }
    }

    @discardableResult
    func addWebsitePrice(title: String, url: String, threshold: Double, below: Bool = true, intervalMinutes: Int = 30) -> WatchTask {
        let task = WatchTask(title: cleanTitle(title, fallback: "Fiyat takibi"), kind: .websitePrice, target: cleanURL(url),
                             condition: below ? .priceBelow(threshold) : .priceAbove(threshold),
                             intervalMinutes: intervalMinutes)
        add(task)
        return task
    }

    @discardableResult
    func addWebsiteText(title: String, url: String, text: String? = nil, intervalMinutes: Int = 30) -> WatchTask {
        let condition: WatchCondition = text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .textContains($0) } ?? .textChanged
        let task = WatchTask(title: cleanTitle(title, fallback: "Site takibi"), kind: .websiteText, target: cleanURL(url),
                             condition: condition, intervalMinutes: intervalMinutes)
        add(task)
        return task
    }

    @discardableResult
    func addGitHubRelease(title: String, repository: String, intervalMinutes: Int = 60) -> WatchTask {
        let repo = GitHubReleaseEndpoint.repositorySlug(from: repository) ?? repository
        let task = WatchTask(title: cleanTitle(title, fallback: repo), kind: .githubRelease, target: repo,
                             condition: .versionChanged, intervalMinutes: intervalMinutes)
        add(task)
        return task
    }

    @discardableResult
    func addSystemMetric(title: String, metric: WatchMetric, threshold: Double, above: Bool = true,
                         appName: String = "", intervalMinutes: Int = 15) -> WatchTask {
        let target = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleanTitle(title, fallback: metric.title)
        let task = WatchTask(title: name, kind: .systemMetric, target: target,
                             condition: above ? .metricAbove(metric, threshold) : .metricBelow(metric, threshold),
                             intervalMinutes: intervalMinutes)
        add(task)
        return task
    }

    func setEnabled(_ task: WatchTask, _ enabled: Bool) {
        update(task.id) { $0.isEnabled = enabled; $0.status = enabled ? .idle : .ok }
    }

    func remove(_ task: WatchTask) {
        tasks.removeAll { $0.id == task.id }
        save()
    }

    func checkDue() async {
        for task in tasks where task.isDue {
            await check(id: task.id, force: false)
        }
    }

    func check(id: UUID, force: Bool = true) async {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        var task = tasks[index]
        guard force || task.isDue else { return }
        guard !checkingIDs.contains(id) else { return }
        checkingIDs.insert(id)
        isChecking = true
        tasks[index].status = .checking
        do {
            let reading = try await reading(for: task)
            let evaluation = WatchEvaluation.evaluate(task: task, reading: reading)
            task.lastValue = reading.displayValue
            task.lastNumericValue = reading.numericValue
            task.baseline = evaluation.baseline ?? task.baseline
            task.lastCheckedAt = Date()
            task.status = evaluation.triggered ? .triggered : .ok
            task.errorMessage = nil
            if evaluation.triggered {
                task.lastTriggeredAt = Date()
                notify(task.kind.symbol, "\(task.title): \(evaluation.message)")
            }
            replace(task)
        } catch {
            task.lastCheckedAt = Date()
            task.status = .failed
            task.errorMessage = error.localizedDescription
            replace(task)
        }
        checkingIDs.remove(id)
        isChecking = !checkingIDs.isEmpty
    }

    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkDue() }
        }
        timer?.tolerance = 20
    }

    private func reading(for task: WatchTask) async throws -> WatchReading {
        switch task.kind {
        case .websitePrice:
            let text = try await fetchText(task.target)
            let price = PriceExtractor.firstPrice(in: text)
            return WatchReading(displayValue: price.map { "₺" + WatchFormatting.number($0) } ?? "Fiyat yok",
                                numericValue: price, rawValue: text)
        case .websiteText:
            let text = try await fetchText(task.target)
            let normalized = WatchEvaluation.normalized(text)
            return WatchReading(displayValue: String(normalized.prefix(90)), rawValue: normalized)
        case .githubRelease:
            let release = try await GitHubReleaseEndpoint.latestRelease(repository: task.target)
            return WatchReading(displayValue: release.tag, rawValue: release.tag)
        case .systemMetric:
            return systemReading(for: task)
        }
    }

    private func fetchText(_ raw: String) async throws -> String {
        var address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.contains("://") { address = "https://" + address }
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme) else {
            throw WatchError.invalidTarget
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("MacB Watcher/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WatchError.httpStatus(http.statusCode)
        }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return HTMLText.plain(from: text)
    }

    private func systemReading(for task: WatchTask) -> WatchReading {
        switch task.condition {
        case .metricAbove(let metric, _), .metricBelow(let metric, _):
            let value = metricValue(metric, target: task.target)
            return WatchReading(displayValue: display(value, for: metric), numericValue: value, rawValue: "\(value)")
        default:
            return WatchReading(displayValue: "Hazır", numericValue: 0, rawValue: "0")
        }
    }

    private func metricValue(_ metric: WatchMetric, target: String) -> Double {
        let snapshot = systemMonitor.snapshot
        switch metric {
        case .cpuPercent:
            return snapshot.cpuUsage
        case .memoryPercent:
            guard snapshot.totalMemory > 0 else { return 0 }
            return Double(snapshot.usedMemory) / Double(snapshot.totalMemory) * 100
        case .batteryPercent:
            return snapshot.batteryPercent ?? 100
        case .appCPUPercent:
            return matchProcess(named: target)?.cpuPercent ?? 0
        case .appMemoryMB:
            return Double(matchProcess(named: target)?.memoryBytes ?? 0) / 1_048_576
        }
    }

    private func matchProcess(named raw: String) -> ProcessUsage? {
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pool = Array((processes.byCPU + processes.byMemory).uniquedByName())
        guard !term.isEmpty else { return pool.first }
        return pool.first { $0.name.compare(term, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            ?? pool.first { $0.name.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    private func display(_ value: Double, for metric: WatchMetric) -> String {
        "\(WatchFormatting.number(value))\(metric.unit)"
    }

    private func update(_ id: UUID, change: (inout WatchTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[index])
        save()
    }

    private func replace(_ task: WatchTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
        save()
    }

    private func load() {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { tasks = []; return }
            let data = try Data(contentsOf: fileURL)
            tasks = try decoder.decode([WatchTask].self, from: data)
        } catch {
            errorMessage = "Takipler okunamadı: \(error.localizedDescription)"
            tasks = []
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(tasks).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            errorMessage = "Takipler kaydedilemedi: \(error.localizedDescription)"
        }
    }

    private func cleanTitle(_ title: String, fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(80))
    }

    private func cleanURL(_ url: String) -> String { url.trimmingCharacters(in: .whitespacesAndNewlines) }
}

private enum WatchError: LocalizedError {
    case invalidTarget
    case httpStatus(Int)
    case githubRepository
    case githubReleaseMissing

    var errorDescription: String? {
        switch self {
        case .invalidTarget: return "Adres geçersiz."
        case .httpStatus(let code): return "Site \(code) döndü."
        case .githubRepository: return "GitHub repo adresi owner/name şeklinde değil."
        case .githubReleaseMissing: return "Release bulunamadı."
        }
    }
}

private enum HTMLText {
    static func plain(from html: String) -> String {
        html.replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct GitHubReleaseEndpoint {
    struct Release: Decodable { let tag_name: String; var tag: String { tag_name } }

    static func repositorySlug(from raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.split(separator: "/").count == 2, !text.contains("://") { return text }
        guard let url = URL(string: text.contains("://") ? text : "https://" + text),
              url.host?.localizedCaseInsensitiveContains("github.com") == true else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        return parts[0] + "/" + parts[1].replacingOccurrences(of: ".git", with: "")
    }

    static func latestRelease(repository raw: String) async throws -> Release {
        guard let repo = repositorySlug(from: raw) else { throw WatchError.githubRepository }
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { throw WatchError.githubReleaseMissing }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw WatchError.httpStatus(http.statusCode) }
        return try JSONDecoder().decode(Release.self, from: data)
    }
}

private extension Array where Element == ProcessUsage {
    func uniquedByName() -> [ProcessUsage] {
        var seen = Set<String>()
        return filter { seen.insert($0.name).inserted }
    }
}
