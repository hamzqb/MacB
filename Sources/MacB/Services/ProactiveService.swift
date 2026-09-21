import AppKit
import EventKit
import MacBCore

/// MacB speaking first: when the user comes back, and when something is
/// worth an interruption.
///
/// Away and back come from the screen locking and unlocking, and from how long
/// it has been since the last keyboard or pointer input — a number macOS keeps
/// anyway, read once every twenty seconds. No camera is involved, except that
/// when the user has put the assistant behind their face, one look decides
/// whether the welcome card may name names.
///
/// Mail is looked at every five minutes, and only when the user turned mail on;
/// only sender, subject and date are read, as everywhere else. Calendar is
/// looked at every minute, only with calendar access already granted.
@MainActor final class ProactiveService {
    private let preferences: Preferences
    private let mail: MailService
    private let jobs: AgentJobStore
    private let briefing: BriefingService
    private let faceUnlock: FaceUnlockService
    private let present: (IslandEvent) -> Void
    private let events = EKEventStore()

    private var timers: [Timer] = []
    private var observers: [NSObjectProtocol] = []
    private var awaySince: Date?
    private var mailSeenAtAway: Set<String> = []

    private var mailSeen: Set<String> = []
    private var hasLookedAtMail = false
    private var meetingsAnnounced: Set<String> = []

    init(preferences: Preferences, mail: MailService, jobs: AgentJobStore, briefing: BriefingService,
         faceUnlock: FaceUnlockService, present: @escaping (IslandEvent) -> Void) {
        self.preferences = preferences
        self.mail = mail
        self.jobs = jobs
        self.briefing = briefing
        self.faceUnlock = faceUnlock
        self.present = present
    }

    func start() {
        guard timers.isEmpty else { return }
        timers.append(repeating(every: 20) { [weak self] in self?.checkPresence() })
        timers.append(repeating(every: 5 * 60) { [weak self] in self?.checkMail() })
        timers.append(repeating(every: 60) { [weak self] in self?.checkMeetings() })
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.left(at: Date()) }
        })
        observers.append(center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cameBack() }
        })
        checkMail()
    }

    func stop() {
        timers.forEach { $0.invalidate() }
        timers = []
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers = []
    }

    private func repeating(every seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: seconds, repeats: true) { _ in Task { @MainActor in work() } }
        timer.tolerance = seconds * 0.2
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    // MARK: - Away and back

    private static var idleSeconds: TimeInterval {
        guard let anyInput = CGEventType(rawValue: UInt32.max) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    private func checkPresence() {
        let idle = Self.idleSeconds
        if awaySince == nil, Presence.isAway(idleSeconds: idle) {
            left(at: Date().addingTimeInterval(-idle))
        } else if awaySince != nil, Presence.isBack(idleSeconds: idle), !ScreenControlService.screenIsLocked {
            cameBack()
        }
    }

    private func left(at date: Date) {
        guard awaySince == nil else { return }
        awaySince = date
        mailSeenAtAway = Set(mail.summary.headers.map(\.id))
    }

    private func cameBack() {
        guard let since = awaySince else { return }
        awaySince = nil
        let awayFor = Date().timeIntervalSince(since)
        guard preferences.returnSummaryEnabled, awayFor >= Presence.summaryAfter else { return }
        let seenBefore = mailSeenAtAway
        Task { [weak self] in
            guard let self else { return }
            var summary = Presence.AwaySummary(awayFor: awayFor)
            if self.preferences.mailEnabled {
                let now = await self.mail.refresh(force: true)
                let fresh = Presence.newMail(now: now.headers, seenBefore: seenBefore)
                summary.newMail = fresh.count
                summary.importantSenders = MailImportance.important(in: fresh, senders: self.preferences.importantSenders)
                    .map(\.senderName)
                self.mailSeen.formUnion(now.headers.map(\.id))
            }
            summary.jobsReady = self.jobs.waiting.count
            summary.nextEvent = self.nextEvent(within: 2 * 60 * 60)
            guard !summary.isEmpty else { return }
            // A job waiting for a yes has its own card with the buttons on
            // it; that one wins, and the rest can wait for the next return.
            guard summary.jobsReady == 0 else { return }
            let showNames = await self.mayShowNames()
            let name = showNames ? NSFullUserName().split(separator: " ").first.map(String.init) : nil
            self.briefing.presentReturn(greeting: Presence.AwaySummary.greeting(name: name),
                                        chips: summary.chips(showNames: showNames),
                                        lines: summary.lines(name: name, showNames: showNames))
        }
    }

    /// Names on the card only for the owner, when the owner asked for that
    /// to be checked. One look, no Touch ID prompt: failing it just means
    /// counts instead of names.
    private func mayShowNames() async -> Bool {
        guard faceUnlock.settings.guards(.assistant) else { return true }
        if faceUnlock.isUnlocked(.assistant) { return true }
        return await faceUnlock.scan()
    }

    // MARK: - Heads-up

    private func checkMail() {
        guard preferences.headsUpEnabled, preferences.mailEnabled, awaySince == nil,
              !ScreenControlService.screenIsLocked else { return }
        Task { [weak self] in
            guard let self else { return }
            let summary = await self.mail.refresh(force: true)
            let worth = HeadsUp.mailWorthTelling(now: summary.headers, seen: self.mailSeen,
                                                 isFirstLook: !self.hasLookedAtMail,
                                                 senders: self.preferences.importantSenders)
            self.hasLookedAtMail = true
            self.mailSeen.formUnion(summary.headers.map(\.id))
            // Senders are the owner's business; a guarded assistant keeps them
            // to itself until it knows who is there.
            guard let first = worth.first,
                  !self.faceUnlock.settings.guards(.assistant) || self.faceUnlock.isUnlocked(.assistant) else { return }
            self.present(HeadsUp.mailEvent(first))
        }
    }

    private func checkMeetings() {
        guard preferences.headsUpEnabled, awaySince == nil,
              EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let now = Date()
        let predicate = events.predicateForEvents(withStart: now, end: now.addingTimeInterval(HeadsUp.meetingLead + 120),
                                                  calendars: nil)
        for event in events.events(matching: predicate) where !event.isAllDay {
            let key = (event.eventIdentifier ?? event.title ?? "") + "|\(event.startDate.timeIntervalSince1970)"
            guard !meetingsAnnounced.contains(key),
                  HeadsUp.announcesMeeting(start: event.startDate, now: now) else { continue }
            meetingsAnnounced.insert(key)
            let guarded = faceUnlock.settings.guards(.assistant) && !faceUnlock.isUnlocked(.assistant)
            present(HeadsUp.meetingEvent(title: guarded ? "Takvimde bir etkinlik" : (event.title ?? "Etkinlik"),
                                         start: event.startDate, now: now))
        }
    }

    private func nextEvent(within seconds: TimeInterval) -> (title: String, minutes: Int)? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }
        let now = Date()
        let predicate = events.predicateForEvents(withStart: now, end: now.addingTimeInterval(seconds), calendars: nil)
        guard let event = events.events(matching: predicate)
            .filter({ !$0.isAllDay && $0.startDate > now })
            .min(by: { $0.startDate < $1.startDate }) else { return nil }
        return (event.title ?? "Etkinlik", Int(event.startDate.timeIntervalSince(now) / 60))
    }
}
