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
        /// The next thing in the calendar today, already written out.
        public var nextEvent: String?
        public var eventCount: Int
        public var reminderCount: Int
        /// Only worth saying when it is low and not charging.
        public var battery: Int?
        public var isCharging: Bool
        /// Assistants that are waiting for an answer right now.
        public var waitingAgents: Int

        public init(weather: String? = nil, nextEvent: String? = nil, eventCount: Int = 0,
                    reminderCount: Int = 0, battery: Int? = nil, isCharging: Bool = false,
                    waitingAgents: Int = 0) {
            self.weather = weather
            self.nextEvent = nextEvent
            self.eventCount = eventCount
            self.reminderCount = reminderCount
            self.battery = battery
            self.isCharging = isCharging
            self.waitingAgents = waitingAgents
        }
    }

    /// Below this, and not plugged in, the battery is worth a sentence.
    public static let lowBattery = 30

    /// The lines of a briefing: the greeting, then only what is actually worth
    /// hearing. A briefing that lists everything every morning stops being
    /// listened to, so an empty calendar and a full battery say nothing.
    public static func lines(for date: Date, name: String?, facts: Facts,
                             calendar: Calendar = .current) -> [String] {
        var lines = [opening(for: date, name: name, calendar: calendar)]
        if let weather = facts.weather, !weather.isEmpty { lines.append(weather) }
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
