import Foundation

/// Whether somebody is at the Mac, and what to tell them when they come back.
///
/// Away is the screen locking, or no keyboard, pointer or trackpad input for
/// a while. Back is the screen unlocking, or input again. A short absence —
/// making tea — is not worth a card; a real one is.
public enum Presence {
    /// Idle this long counts as having left.
    public static let awayAfterIdle: TimeInterval = 10 * 60
    /// Gone for less than this, and coming back is not an event.
    public static let summaryAfter: TimeInterval = 10 * 60
    /// Input this recent means somebody is here.
    public static let backWithinIdle: TimeInterval = 20

    public static func isAway(idleSeconds: TimeInterval) -> Bool { idleSeconds >= awayAfterIdle }

    public static func isBack(idleSeconds: TimeInterval) -> Bool { idleSeconds < backWithinIdle }

    /// What happened while the user was gone.
    public struct AwaySummary: Equatable, Sendable {
        public var awayFor: TimeInterval
        public var newMail: Int
        /// Senders of the new important mail, first names only.
        public var importantSenders: [String]
        public var jobsReady: Int
        /// The next calendar event within two hours, if any.
        public var nextEvent: (title: String, minutes: Int)?

        public init(awayFor: TimeInterval, newMail: Int = 0, importantSenders: [String] = [],
                    jobsReady: Int = 0, nextEvent: (title: String, minutes: Int)? = nil) {
            self.awayFor = awayFor
            self.newMail = newMail
            self.importantSenders = importantSenders
            self.jobsReady = jobsReady
            self.nextEvent = nextEvent
        }

        public static func == (lhs: AwaySummary, rhs: AwaySummary) -> Bool {
            lhs.awayFor == rhs.awayFor && lhs.newMail == rhs.newMail
                && lhs.importantSenders == rhs.importantSenders && lhs.jobsReady == rhs.jobsReady
                && lhs.nextEvent?.title == rhs.nextEvent?.title && lhs.nextEvent?.minutes == rhs.nextEvent?.minutes
        }

        /// Nothing happened: no card. "Welcome back" alone is noise.
        public var isEmpty: Bool { newMail == 0 && jobsReady == 0 && nextEvent == nil }

        public static func greeting(name: String?) -> String {
            guard let name, !name.isEmpty else { return "Tekrar hoş geldin." }
            return "Tekrar hoş geldin \(name)."
        }

        /// The card's chips. Without `showNames` — the face at the Mac was not
        /// recognised — senders and event titles stay out and only counts show.
        public func chips(showNames: Bool) -> [Briefing.Chip] {
            var chips: [Briefing.Chip] = []
            if newMail > 0 {
                if showNames, let first = importantSenders.first {
                    let more = importantSenders.count > 1 ? " +\(importantSenders.count - 1)" : ""
                    chips.append(Briefing.Chip(symbol: "envelope.badge.fill", text: first + more, isUrgent: true))
                    if newMail > importantSenders.count {
                        chips.append(Briefing.Chip(symbol: "envelope", text: "\(newMail) yeni mail"))
                    }
                } else {
                    chips.append(Briefing.Chip(symbol: "envelope", text: "\(newMail) yeni mail",
                                               isUrgent: !importantSenders.isEmpty))
                }
            }
            if jobsReady > 0 {
                chips.append(Briefing.Chip(symbol: "checklist", text: "\(jobsReady) iş hazır", isUrgent: true))
            }
            if let event = nextEvent {
                let when = event.minutes <= 0 ? "şimdi" : "\(event.minutes) dk"
                chips.append(Briefing.Chip(symbol: "calendar",
                                           text: showNames ? "\(when) · \(event.title)" : "\(when) sonra etkinlik",
                                           isUrgent: event.minutes <= 15))
            }
            return Array(chips.prefix(Briefing.maximumChips))
        }

        /// The sentences, for reading out.
        public func lines(name: String?, showNames: Bool) -> [String] {
            var lines = [AwaySummary.greeting(name: name)]
            if newMail > 0 {
                if showNames, !importantSenders.isEmpty {
                    lines.append("Sen yokken \(newMail) mail geldi, \(importantSenders.joined(separator: " ve ")) önemli görünüyor.")
                } else {
                    lines.append("Sen yokken \(newMail) mail geldi.")
                }
            }
            if jobsReady > 0 { lines.append("\(jobsReady) iş hazır, onayını bekliyor.") }
            if let event = nextEvent {
                lines.append(showNames ? "\(event.minutes) dakika sonra \(event.title) var."
                                       : "\(event.minutes) dakika sonra bir etkinliğin var.")
            }
            return lines
        }
    }

    /// Headers that were not there when the user left.
    public static func newMail(now: [MailHeader], seenBefore: Set<String>) -> [MailHeader] {
        now.filter { !seenBefore.contains($0.id) }
    }
}

/// Telling the user about something before they ask.
public enum HeadsUp {
    /// How far ahead a meeting is announced, and the tolerance either side so
    /// a minute-long poll cannot miss it.
    public static let meetingLead: TimeInterval = 10 * 60
    public static let meetingWindow: TimeInterval = 90

    /// Whether an event starting at `start` should be announced now.
    public static func announcesMeeting(start: Date, now: Date) -> Bool {
        let lead = start.timeIntervalSince(now)
        return lead > 0 && abs(lead - meetingLead) <= meetingWindow
    }

    public static func meetingEvent(title: String, start: Date, now: Date) -> IslandEvent {
        let minutes = max(1, Int((start.timeIntervalSince(now) / 60).rounded()))
        return IslandEvent(kind: .headsUp, title: "\(minutes) dk sonra", detail: title, symbol: "calendar")
    }

    /// Mail worth interrupting for: new and important, and never on the first
    /// look — everything is "new" to a MacB that has just started.
    public static func mailWorthTelling(now: [MailHeader], seen: Set<String>, isFirstLook: Bool,
                                        senders: [String]) -> [MailHeader] {
        guard !isFirstLook else { return [] }
        return MailImportance.important(in: Presence.newMail(now: now, seenBefore: seen), senders: senders)
    }

    public static func mailEvent(_ header: MailHeader) -> IslandEvent {
        IslandEvent(kind: .headsUp, title: "Önemli mail · \(header.senderName)",
                    detail: MailParsing.clip(header.subject), symbol: "envelope.badge.fill")
    }
}
