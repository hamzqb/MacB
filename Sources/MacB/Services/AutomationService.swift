import AppKit
import Combine
import MacBCore

/// Runs the user's rules.
///
/// Everything it listens to is already being watched for the island's own sake,
/// so switching automation on costs nothing new: no extra polling, no extra
/// permission, no background helper. Everything it does is something the user
/// could do by hand, and nothing it does removes or overwrites anything.
@MainActor final class AutomationService: ObservableObject {
    @Published private(set) var rules: [AutomationRule] = []
    /// What ran last, for the settings list to show that a rule really works.
    @Published private(set) var lastRun: (title: String, at: Date)?

    private var engine = AutomationEngine()
    private var subscriptions: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var isEnabled = false
    private var lastCharging: Bool?
    private var lastPlaying: Bool?
    private var lastTimerActive: Bool?

    private let media: MediaService
    private let timer: TimerService
    private let systemMonitor: SystemMonitorService
    private let lid: LidAngleService
    private let store: AutomationStore
    /// How a rule speaks to the island. Set by the controller once it exists.
    var notice: ((String) -> Void)?

    init(media: MediaService, timer: TimerService, systemMonitor: SystemMonitorService,
         lid: LidAngleService, store: AutomationStore = AutomationStore()) {
        self.media = media
        self.timer = timer
        self.systemMonitor = systemMonitor
        self.lid = lid
        self.store = store
        rules = store.load()
        engine.setRules(rules)
    }

    // MARK: - Rules

    func add(_ rule: AutomationRule) {
        rules.append(rule)
        persist()
    }

    func update(_ rule: AutomationRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        persist()
    }

    func remove(_ rule: AutomationRule) {
        rules.removeAll { $0.id == rule.id }
        persist()
    }

    func setEnabled(_ rule: AutomationRule, _ enabled: Bool) {
        guard var found = rules.first(where: { $0.id == rule.id }) else { return }
        found.isEnabled = enabled
        update(found)
    }

    /// Runs a rule now, so somebody can see what it does before trusting it to
    /// an event they will not be watching.
    func test(_ rule: AutomationRule) {
        guard rule.action.isSafe else { return }
        perform(rule.action, from: rule.title)
    }

    private func persist() {
        engine.setRules(rules)
        store.save(rules)
    }

    // MARK: - Listening

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled { listen() } else { stopListening() }
    }

    private func stopListening() {
        subscriptions.removeAll()
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
        lastCharging = nil; lastPlaying = nil; lastTimerActive = nil
    }

    private func listen() {
        systemMonitor.$snapshot.sink { [weak self] snapshot in
            Task { @MainActor in self?.powerChanged(snapshot) }
        }.store(in: &subscriptions)

        media.$isPlaying.removeDuplicates().sink { [weak self] playing in
            Task { @MainActor in self?.playbackChanged(playing) }
        }.store(in: &subscriptions)

        timer.$remaining.sink { [weak self] _ in
            Task { @MainActor in self?.timerChanged() }
        }.store(in: &subscriptions)

        lid.didOpen.sink { [weak self] in
            Task { @MainActor in self?.handle(.lidOpened) }
        }.store(in: &subscriptions)
        lid.willFold.sink { [weak self] in
            Task { @MainActor in self?.handle(.lidClosing) }
        }.store(in: &subscriptions)

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            guard let identifier = Self.bundleIdentifier(in: note) else { return }
            Task { @MainActor in self?.handle(.appLaunched(identifier)) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            guard let identifier = Self.bundleIdentifier(in: note) else { return }
            Task { @MainActor in self?.handle(.appQuit(identifier)) }
        })
    }

    private nonisolated static func bundleIdentifier(in note: Notification) -> String? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
    }

    // MARK: - Turning readings into events

    private func powerChanged(_ snapshot: SystemSnapshot) {
        if let was = lastCharging, was != snapshot.isCharging {
            handle(snapshot.isCharging ? .chargerConnected : .chargerDisconnected)
        }
        lastCharging = snapshot.isCharging
        if let percent = snapshot.batteryPercent {
            let level = Int(percent.rounded())
            handle(.batteryLevel(level))
            if snapshot.isCharging { handle(.chargingLevel(level)) }
        }
    }

    private func playbackChanged(_ playing: Bool) {
        // The first reading is the state MacB started in, not a change.
        defer { lastPlaying = playing }
        guard let was = lastPlaying, was != playing else { return }
        handle(playing ? .mediaStarted : .mediaStopped)
    }

    private func timerChanged() {
        let active = timer.isActive
        defer { lastTimerActive = active }
        guard lastTimerActive == true, !active else { return }
        handle(.timerFinished)
    }

    private func handle(_ event: AutomationEvent) {
        guard isEnabled else { return }
        for action in engine.actions(for: event) {
            let title = rules.first { $0.action == action }?.title ?? "Kural"
            perform(action, from: title)
        }
    }

    // MARK: - Doing it

    private func perform(_ action: AutomationAction, from title: String) {
        lastRun = (title, Date())
        switch action {
        case .openApplication(let identifier, _):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case .openLink(let link):
            // Checked again here rather than trusted from storage: a rules file
            // edited by hand must not be able to open an arbitrary scheme.
            guard action.isSafe, let url = URL(string: link.trimmingCharacters(in: .whitespaces)) else { return }
            NSWorkspace.shared.open(url)
        case .showNotice(let text):
            notice?(text)
        case .startTimer(let minutes):
            timer.start(minutes: Double(minutes))
        case .pauseMedia:
            if media.isPlaying { media.playPause() }
        case .runShortcut(let name):
            runShortcut(named: name)
        }
    }

    /// Runs one of the user's own Shortcuts.
    ///
    /// No shell: the name is one argument to one executable, so nothing in it
    /// can become a second command however it is spelled.
    private func runShortcut(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", trimmed]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

/// Where the rules live.
///
/// A file in Application Support rather than preferences, so a long list of
/// rules does not sit inside the defaults database and can be backed up,
/// inspected and copied between Macs like anything else the user owns.
final class AutomationStore {
    private let url: URL

    init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            let directory = base.appendingPathComponent("MacB", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.url = directory.appendingPathComponent("automation.json")
        }
    }

    func load() -> [AutomationRule] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([AutomationRule].self, from: data)) ?? []
    }

    func save(_ rules: [AutomationRule]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(rules) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
