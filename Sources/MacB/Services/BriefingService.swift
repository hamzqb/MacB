import AVFoundation
import AppKit
import Combine
import EventKit
import Foundation
import MacBCore

/// The first thing MacB says in the morning.
///
/// Once a day, when the Mac is woken or unlocked after the chosen hour: a
/// greeting by name, the weather, what is on today, and anything that wants
/// attention. Then it stops. A briefing that appears twice, or at two in the
/// morning, is an alarm nobody asked for.
///
/// Everything in it is already on this Mac. Nothing is sent anywhere to build
/// it: the weather comes from the widget's own reading, the calendar is read
/// locally and only when access has already been granted, and the voice is
/// macOS's own — so the morning briefing costs nothing and needs no key.
@MainActor final class BriefingService: ObservableObject {
    /// The briefing on screen right now, if any.
    @Published private(set) var lines: [String] = []
    /// The same briefing as chips, for the island. Built from the same facts
    /// the spoken lines are, so the two can never say different things.
    @Published private(set) var chips: [Briefing.Chip] = []
    @Published private(set) var givenAt: Date?
    /// The greeting on its own, so the island can set it apart from the facts.
    @Published private(set) var greeting = ""
    @Published private(set) var isSpeaking = false

    private let preferences: Preferences
    private let weather: WeatherService
    private let monitor: SystemMonitorService
    private let activity: AIActivityService
    private let events = EKEventStore()
    private let speaker = AVSpeechSynthesizer()
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var speechDelegate: SpeechFinished?

    /// Where the date of the last briefing is remembered, so it survives a
    /// restart. A date and nothing else.
    private static let lastKey = "briefingLastGiven"

    init(preferences: Preferences, weather: WeatherService, monitor: SystemMonitorService,
         activity: AIActivityService) {
        self.preferences = preferences
        self.weather = weather
        self.monitor = monitor
        self.activity = activity
        givenAt = UserDefaults.standard.object(forKey: Self.lastKey) as? Date
        let delegate = SpeechFinished { [weak self] in self?.isSpeaking = false }
        speechDelegate = delegate
        speaker.delegate = delegate
    }

    var isVisible: Bool { !lines.isEmpty }

    // MARK: - When

    func startObserving() {
        stopObserving()
        let centre = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(centre.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.considerBriefing() }
            })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.considerBriefing() }
            })
        // A Mac left running all night crosses the hour without waking, so the
        // clock is checked too — quarter-hourly, which is close enough for a
        // greeting and cheap enough to leave on.
        let timer = Timer(timeInterval: 900, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.considerBriefing() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        considerBriefing()
    }

    func stopObserving() {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        DistributedNotificationCenter.default().removeObserver(self)
        observers = []
        timer?.invalidate()
        timer = nil
    }

    /// Gives the briefing if one is due. Called often; says nothing nearly
    /// always.
    func considerBriefing() {
        guard preferences.briefingEnabled else { return }
        guard Briefing.isDue(now: Date(), lastGiven: givenAt, hour: preferences.briefingHour) else { return }
        give()
    }

    /// Gives the briefing now, whether or not one is due. This is what the menu
    /// item and the ring slice call.
    func give(speaking: Bool? = nil) {
        let now = Date()
        givenAt = now
        UserDefaults.standard.set(now, forKey: Self.lastKey)
        Task { [weak self] in
            guard let self else { return }
            let facts = await self.gather()
            self.lines = Briefing.lines(for: now, name: Self.firstName(), facts: facts)
            self.greeting = Briefing.opening(for: now, name: Self.firstName())
            self.chips = Briefing.chips(for: facts)
            if speaking ?? self.preferences.briefingSpeaks { self.speak() }
        }
    }

    /// Fills the card in without gathering anything.
    ///
    /// For the measuring probe, which has to draw the real view to find out
    /// whether it fits the height the island reserves for it, and must not
    /// touch the weather, the calendar or the battery to do so.
    func preview(greeting: String, chips: [Briefing.Chip], lines: [String]) {
        self.greeting = greeting
        self.chips = chips
        self.lines = lines
        givenAt = Date()
    }

    /// Takes the briefing off the island.
    func dismiss() {
        lines = []
        chips = []
        stopSpeaking()
    }

    // MARK: - What

    private func gather() async -> Briefing.Facts {
        var facts = Briefing.Facts()
        if weather.snapshot == nil { weather.refresh(force: true) }
        // A short wait rather than a long one: if the weather is slow, the
        // briefing goes out without it instead of arriving late.
        for _ in 0..<15 where weather.snapshot == nil && weather.errorMessage == nil {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if let now = weather.snapshot {
            facts.weather = "\(now.place) \(now.temperature) derece, \(now.condition.lowercased())."
            facts.weatherShort = "\(now.temperature)° \(now.condition.lowercased())"
            facts.weatherSymbol = now.symbol
        }
        let snapshot = monitor.snapshot
        facts.battery = snapshot.batteryPercent.map { Int($0.rounded()) }
        facts.isCharging = snapshot.isCharging
        facts.waitingAgents = activity.statuses.filter(\.isRunning).count
        let calendar = readCalendar()
        facts.eventCount = calendar.count
        facts.nextEvent = calendar.first
        facts.reminderCount = await readReminderCount()
        return facts
    }

    /// Today's remaining events, already written out.
    ///
    /// Only when the user has already granted calendar access: the morning
    /// briefing never puts a permission prompt on screen by itself.
    private func readCalendar() -> [String] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let calendar = Calendar.current
        let now = Date()
        guard let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) else { return [] }
        let predicate = events.predicateForEvents(withStart: now, end: end, calendars: nil)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "HH:mm"
        return events.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map { "\(formatter.string(from: $0.startDate)) \($0.title ?? "başlıksız")" }
    }

    private func readReminderCount() async -> Int {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return 0 }
        let predicate = events.predicateForIncompleteReminders(withDueDateStarting: nil, ending: Date(),
                                                              calendars: nil)
        return await withCheckedContinuation { continuation in
            events.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders?.count ?? 0)
            }
        }
    }

    private static func firstName() -> String? {
        let full = NSFullUserName().trimmingCharacters(in: .whitespaces)
        guard !full.isEmpty else { return nil }
        return full.split(separator: " ").first.map(String.init)
    }

    // MARK: - Voice

    /// Read aloud by macOS itself, not by a model: nothing is sent, nothing is
    /// billed, and it works with no key and no network.
    func speak() {
        guard !lines.isEmpty else { return }
        stopSpeaking()
        let utterance = AVSpeechUtterance(string: lines.joined(separator: " "))
        utterance.voice = Self.turkishVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        isSpeaking = true
        speaker.speak(utterance)
    }

    func stopSpeaking() {
        if speaker.isSpeaking { speaker.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    /// The best Turkish voice installed, preferring the higher-quality ones the
    /// user may have downloaded.
    private static func turkishVoice() -> AVSpeechSynthesisVoice? {
        let turkish = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("tr") }
        return turkish.first { $0.quality == .premium }
            ?? turkish.first { $0.quality == .enhanced }
            ?? turkish.first
            ?? AVSpeechSynthesisVoice(language: "tr-TR")
    }

    /// Tells the service when the voice has finished, so the island can stop
    /// showing it as speaking.
    private final class SpeechFinished: NSObject, AVSpeechSynthesizerDelegate {
        private let finished: () -> Void

        init(finished: @escaping () -> Void) {
            self.finished = finished
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            Task { @MainActor in self.finished() }
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            Task { @MainActor in self.finished() }
        }
    }
}
