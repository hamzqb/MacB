import AppKit
import Combine
import Foundation
import MacBCore

/// The user's own scenarios, and the one place that runs them.
///
/// Every step is something MacB already does from the ring or the menu; a
/// scenario only spares the user doing them one at a time. The steps come from
/// this file and nowhere else — the assistant may ask for a scenario by name,
/// but it cannot write one, add a step to one, or run a step that is not in it.
@MainActor final class ScenarioStore: ObservableObject {
    @Published private(set) var scenarios: [Scenario] = []
    /// The scenario that ran last, for the island's toast.
    @Published private(set) var lastRun: String?

    private let url: URL
    private var isUnreadable = false
    private let keepAwake: KeepAwakeService
    private let arrangements: WindowArrangementService
    private let media: MediaService
    private let timer: TimerService

    init(url: URL? = nil, keepAwake: KeepAwakeService, arrangements: WindowArrangementService,
         media: MediaService, timer: TimerService) {
        self.url = url ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacB", isDirectory: true)
            .appendingPathComponent("scenarios.json")
        self.keepAwake = keepAwake
        self.arrangements = arrangements
        self.media = media
        self.timer = timer
        load()
    }

    // MARK: - Editing

    @discardableResult
    func add(name: String) -> Scenario? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, scenarios.count < ScenarioMatching.maximum,
              !scenarios.contains(where: { ScenarioMatching.normalise($0.name) == ScenarioMatching.normalise(trimmed) })
        else { return nil }
        let scenario = Scenario(name: trimmed)
        scenarios.append(scenario)
        save()
        return scenario
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = scenarios.firstIndex(where: { $0.id == id }) else { return }
        scenarios[index].name = trimmed
        save()
    }

    func remove(_ id: UUID) {
        scenarios.removeAll { $0.id == id }
        save()
    }

    func addStep(_ step: ScenarioStep, to id: UUID) {
        guard let index = scenarios.firstIndex(where: { $0.id == id }) else { return }
        scenarios[index].steps.append(step)
        save()
    }

    func replaceStep(at position: Int, in id: UUID, with step: ScenarioStep) {
        guard let index = scenarios.firstIndex(where: { $0.id == id }),
              scenarios[index].steps.indices.contains(position) else { return }
        scenarios[index].steps[position] = step
        save()
    }

    func removeStep(at position: Int, in id: UUID) {
        guard let index = scenarios.firstIndex(where: { $0.id == id }),
              scenarios[index].steps.indices.contains(position) else { return }
        scenarios[index].steps.remove(at: position)
        save()
    }

    // MARK: - Running

    /// Runs a scenario by name and says what it did.
    ///
    /// Steps that cannot run are skipped rather than stopping the rest: a
    /// missing application should not leave the windows half-arranged.
    @discardableResult
    func run(named spoken: String) async -> String {
        guard let scenario = ScenarioMatching.find(spoken, in: scenarios) else {
            return "\u{201C}\(spoken)\u{201D} diye bir senaryo yok."
        }
        return await run(scenario)
    }

    @discardableResult
    func run(_ scenario: Scenario) async -> String {
        var ran = 0
        for step in scenario.steps where step.isComplete {
            if await perform(step) { ran += 1 }
        }
        lastRun = scenario.name
        return scenario.summary(ran: ran)
    }

    private func perform(_ step: ScenarioStep) async -> Bool {
        switch step {
        case .keepAwake(let minutes):
            return keepAwake.start(minutes: minutes)
        case .arrangement(let name):
            let wanted = ScenarioMatching.normalise(name)
            guard let arrangement = arrangements.arrangements.first(where: {
                ScenarioMatching.normalise($0.name) == wanted
            }) else { return false }
            return arrangements.apply(arrangement) > 0
        case .openApplication(let name):
            return Self.openApplication(named: name)
        case .openWebsite(let raw):
            let text = raw.contains("://") ? raw : "https://" + raw
            guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http" else { return false }
            return NSWorkspace.shared.open(url)
        case .media(let play):
            // One control, two meanings: only touch it when the state is not
            // already the one the scenario wants.
            guard media.isPlaying != play else { return true }
            media.playPause()
            return true
        case .volume(let percent):
            return Self.setVolume(percent)
        case .timer(let minutes):
            timer.start(minutes: Double(minutes))
            return true
        case .shortcut(let name):
            return Self.runShortcut(named: name)
        }
    }

    private static func openApplication(named name: String) -> Bool {
        let wanted = ScenarioMatching.normalise(name)
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            ScenarioMatching.normalise($0.localizedName ?? "") == wanted
        }) {
            return running.activate(options: [])
        }
        for directory in ["/Applications", "/System/Applications",
                          NSHomeDirectory() + "/Applications"] {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name + ".app")
            if FileManager.default.fileExists(atPath: candidate.path) {
                NSWorkspace.shared.open(candidate)
                return true
            }
        }
        return false
    }

    /// The output volume, through the one scripting call MacB makes.
    ///
    /// The number is clamped and written by MacB, never interpolated from
    /// anything typed elsewhere, so no name can become a script.
    private static func setVolume(_ percent: Int) -> Bool {
        let level = min(100, max(0, percent))
        let script = NSAppleScript(source: "set volume output volume \(level)")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        return error == nil
    }

    /// Runs one of the user's own Shortcuts by name, through Apple's own tool.
    ///
    /// The name comes from this file, which only the settings window writes.
    /// It is passed as an argument rather than through a shell, so a name with
    /// a quote or a semicolon in it is a name, not a command.
    private static func runShortcut(named name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Storage

    private func load() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Scenario].self, from: data) else {
            // A file that exists but cannot be read is not an empty one: never
            // write over it, or one bad parse quietly erases every scenario.
            isUnreadable = true
            return
        }
        scenarios = decoded
    }

    private func save() {
        guard !isUnreadable else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(scenarios) else { return }
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
