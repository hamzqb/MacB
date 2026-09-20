import Foundation

/// The short thing MacB says when the day starts.
///
/// Pure: what it greets you with, what it decides is worth mentioning, and
/// whether it has already been said today — all of it provable without a
/// calendar, a battery or a network.
public enum Briefing {
    /// The greeting for the hour, in Turkish, the way somebody actually
    /// greets you: morning is morning, and midnight is not "good morning".
    public static func greeting(hour: Int) -> String {
        switch hour {
        case 5..<11: return "Günaydın"
        case 11..<18: return "İyi günler"
        case 18..<22: return "İyi akşamlar"
        default: return "İyi geceler"
        }
    }

    public static func greeting(for date: Date, calendar: Calendar = .current) -> String {
        greeting(hour: calendar.component(.hour, from: date))
    }

    /// The opening line, with a name when there is one worth using.
    public static func opening(for date: Date, name: String?, calendar: Calendar = .current) -> String {
        let hello = greeting(for: date, calendar: calendar)
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return hello + "." }
        return "\(hello) \(name)."
    }

    /// Everything the briefing might mention, in the order it should be said.
    public struct Facts: Equatable, Sendable {
        public var weather: String?
        /// The same weather, short enough to sit in a chip: "25° kapalı".
        public var weatherShort: String?
        /// The symbol the weather service already chose for it.
        public var weatherSymbol: String?
        /// The next thing in the calendar today, already written out.
        public var nextEvent: String?
        public var eventCount: Int
        public var reminderCount: Int
        /// Only worth saying when it is low and not charging.
        public var battery: Int?
        public var isCharging: Bool
        /// Assistants that are waiting for an answer right now.
        public var waitingAgents: Int
        /// The inbox, already summarised. Built by the mail service rather
        /// than here, because deciding what is important needs the user's own
        /// list of senders and this file has no business holding one.
        public var mailChip: Chip?
        public var mailLine: String?

        public init(weather: String? = nil, weatherShort: String? = nil, weatherSymbol: String? = nil,
                    nextEvent: String? = nil, eventCount: Int = 0,
                    reminderCount: Int = 0, battery: Int? = nil, isCharging: Bool = false,
                    waitingAgents: Int = 0, mailChip: Chip? = nil, mailLine: String? = nil) {
            self.weather = weather
            self.weatherShort = weatherShort
            self.weatherSymbol = weatherSymbol
            self.nextEvent = nextEvent
            self.eventCount = eventCount
            self.reminderCount = reminderCount
            self.battery = battery
            self.isCharging = isCharging
            self.waitingAgents = waitingAgents
            self.mailChip = mailChip
            self.mailLine = mailLine
        }
    }

    /// Below this, and not plugged in, the battery is worth a sentence.
    public static let lowBattery = 30

    /// One fact, small enough to read at a glance.
    ///
    /// The spoken briefing is sentences, because that is what a voice can say.
    /// The one on screen is not: five stacked grey sentences is a paragraph
    /// nobody reads in the second the island is open. The same facts become a
    /// row of chips — a glyph and two or three words each — so the weather,
    /// the next thing and the battery are found by shape rather than by
    /// reading. Both come from the same `Facts`, so they can never disagree.
    public struct Chip: Equatable, Sendable, Identifiable {
        public var symbol: String
        public var text: String
        /// A chip that is about something the user should act on.
        public var isUrgent: Bool

        public init(symbol: String, text: String, isUrgent: Bool = false) {
            self.symbol = symbol
            self.text = text
            self.isUrgent = isUrgent
        }

        public var id: String { symbol + "|" + text }
    }

    /// At most this many chips. Past four the row wraps, and a wrapped row of
    /// chips is the paragraph they were meant to replace.
    public static let maximumChips = 4

    public static func chips(for facts: Facts) -> [Chip] {
        var chips: [Chip] = []
        if let short = facts.weatherShort, !short.isEmpty {
            chips.append(Chip(symbol: facts.weatherSymbol ?? "cloud.sun.fill", text: short))
        }
        if let mail = facts.mailChip { chips.append(mail) }
        if let next = facts.nextEvent, !next.isEmpty {
            let more = facts.eventCount > 1 ? " +\(facts.eventCount - 1)" : ""
            chips.append(Chip(symbol: "calendar", text: next + more))
        } else if facts.eventCount == 0 {
            chips.append(Chip(symbol: "calendar", text: "Takvim boş"))
        }
        if facts.reminderCount > 0 {
            chips.append(Chip(symbol: "checklist", text: "\(facts.reminderCount) hatırlatıcı"))
        }
        if facts.waitingAgents > 0 {
            chips.append(Chip(symbol: "sparkles", text: "\(facts.waitingAgents) asistan bekliyor", isUrgent: true))
        }
        if let battery = facts.battery, battery <= lowBattery, !facts.isCharging {
            chips.append(Chip(symbol: "battery.25", text: "%\(battery)", isUrgent: true))
        }
        // An urgent chip is the reason the briefing is worth looking at, so it
        // survives the cut when there are more facts than room.
        if chips.count > maximumChips {
            let urgent = chips.filter(\.isUrgent)
            let rest = chips.filter { !$0.isUrgent }
            chips = Array((urgent + rest).prefix(maximumChips))
        }
        return chips
    }

    /// The lines of a briefing: the greeting, then only what is actually worth
    /// hearing. A briefing that lists everything every morning stops being
    /// listened to, so an empty calendar and a full battery say nothing.
    public static func lines(for date: Date, name: String?, facts: Facts,
                             calendar: Calendar = .current) -> [String] {
        var lines = [opening(for: date, name: name, calendar: calendar)]
        if let weather = facts.weather, !weather.isEmpty { lines.append(weather) }
        if let mail = facts.mailLine, !mail.isEmpty { lines.append(mail) }
        if let next = facts.nextEvent, !next.isEmpty {
            if facts.eventCount > 1 {
                lines.append("Bugün \(facts.eventCount) şey var, ilki: \(next)")
            } else {
                lines.append("Bugün: \(next)")
            }
        } else if facts.eventCount == 0 {
            lines.append("Takvimin bugün boş.")
        }
        if facts.reminderCount > 0 {
            lines.append("\(facts.reminderCount) hatırlatıcı bekliyor.")
        }
        if let battery = facts.battery, battery <= lowBattery, !facts.isCharging {
            lines.append("Pil yüzde \(battery); fişe takmak isteyebilirsin.")
        }
        if facts.waitingAgents > 0 {
            lines.append(facts.waitingAgents == 1 ? "Bir kodlama oturumu seni bekliyor."
                                                  : "\(facts.waitingAgents) kodlama oturumu seni bekliyor.")
        }
        return lines
    }

    /// The whole briefing as one paragraph, for reading aloud.
    public static func spoken(for date: Date, name: String?, facts: Facts,
                              calendar: Calendar = .current) -> String {
        lines(for: date, name: name, facts: facts, calendar: calendar).joined(separator: " ")
    }

    /// Whether a briefing is due.
    ///
    /// Once a day, at or after the chosen hour, and never late at night: a Mac
    /// woken at two in the morning does not want to be told good morning. The
    /// window closes six hours after the chosen hour, so a Mac that stays shut
    /// until evening is simply not briefed that day.
    public static func isDue(now: Date, lastGiven: Date?, hour: Int,
                             calendar: Calendar = .current) -> Bool {
        let currentHour = calendar.component(.hour, from: now)
        guard currentHour >= hour, currentHour < min(hour + 6, 23) else { return false }
        guard let lastGiven else { return true }
        return !calendar.isDate(lastGiven, inSameDayAs: now)
    }

    /// The hours that may be chosen in Settings.
    public static let hourChoices = Array(5...12)
}
