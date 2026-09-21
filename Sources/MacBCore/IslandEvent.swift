import CoreGraphics
import Foundation

/// Something worth interrupting the island for, shown for a moment and then gone.
///
/// The island is normally passive: it waits for the pointer. An event is the
/// exception, so the rules for what qualifies live here rather than in a view.
/// Each case is a thing the user just did, which is why a brief takeover is not
/// an interruption but a confirmation.
public struct IslandEvent: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case nowPlaying, charging, unplugged, batteryLow, welcome, lidClosing, rule
        /// Something worth knowing before being asked: important mail, a
        /// meeting about to start.
        case headsUp
    }

    public let kind: Kind
    public let title: String
    public let detail: String?
    /// 0...1 when the event has a level to show, nil when it does not.
    public let progress: Double?
    public let symbol: String

    public init(kind: Kind, title: String, detail: String? = nil,
                progress: Double? = nil, symbol: String) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.progress = progress
        self.symbol = symbol
    }

    /// How long the island stays open for this event.
    ///
    /// Long enough to read, and no longer. A track change is one title; a
    /// warning is worth a beat more.
    public var duration: TimeInterval {
        switch kind {
        case .nowPlaying: return 2.4
        case .charging, .unplugged: return 2.0
        case .batteryLow: return 3.0
        case .welcome: return 2.8
        case .rule: return 2.6
        case .headsUp: return 4.5
        // Long enough to survive a slow close: the island has to still be there
        // to fold, and it leaves with the screen either way.
        case .lidClosing: return 6.0
        }
    }

    /// Whether a newer event of the same kind simply replaces this one rather
    /// than queueing behind it. A run of changes must not queue thirty panels.
    public func supersedes(_ other: IslandEvent) -> Bool {
        kind == other.kind
    }

    /// An event only outranks what is already showing when it is at least as
    /// important. Otherwise the quieter one waits, and a charger notice cannot
    /// push a low-battery warning off the screen.
    public var priority: Int {
        switch kind {
        case .batteryLow: return 3
        case .welcome: return 3
        case .rule: return 3
        case .headsUp: return 3
        case .lidClosing: return 4
        case .charging, .unplugged: return 1
        case .nowPlaying: return 0
        }
    }

    public func outranks(_ other: IslandEvent) -> Bool {
        supersedes(other) || priority >= other.priority
    }
}

public extension IslandEvent {
    static func nowPlaying(title: String, artist: String) -> IslandEvent {
        IslandEvent(kind: .nowPlaying, title: title,
                    detail: artist.isEmpty ? nil : artist,
                    progress: nil, symbol: "music.note")
    }

    static func charging(_ percent: Int?) -> IslandEvent {
        IslandEvent(kind: .charging, title: "Şarj oluyor",
                    detail: percent.map { "\($0)%" },
                    progress: percent.map { Double($0) / 100 }, symbol: "bolt.fill")
    }

    static func unplugged(_ percent: Int?) -> IslandEvent {
        IslandEvent(kind: .unplugged, title: "Pilde",
                    detail: percent.map { "\($0)%" },
                    progress: percent.map { Double($0) / 100 }, symbol: "battery.50")
    }

    static func batteryLow(_ percent: Int) -> IslandEvent {
        IslandEvent(kind: .batteryLow, title: "Pil azaldı",
                    detail: "\(percent)%", progress: Double(percent) / 100,
                    symbol: "battery.25")
    }

    /// The moment the lid comes back up, or nothing at all.
    ///
    /// Shown with the same machinery as a charger notice, because that is exactly
    /// what it is: a line that appears, is read, and leaves on its own.
    ///
    /// Nil when the user has not written a line. Opening the lid is the one
    /// moment the machine is guaranteed to have the person's attention, and
    /// spending it on a greeting they did not ask for is the app talking for
    /// the sake of talking. An empty field is not "pick something for me", it
    /// is "say nothing" — the clock-driven greeting is still there for whoever
    /// wants it, they just have to type it.
    static func welcome(hour: Int, time: String, batteryPercent: Int?,
                        custom: String? = nil) -> IslandEvent? {
        guard let title = customTitle(custom) else { return nil }
        let detail = [time, batteryPercent.map { "%\($0)" }].compactMap { $0 }.joined(separator: " · ")
        return IslandEvent(kind: .welcome, title: title, detail: detail,
                           progress: nil, symbol: symbolForGreeting(hour))
    }

    /// The moment the lid starts going down, or nothing at all.
    ///
    /// The island is invisible when closed, so this is what gets put on screen
    /// for the hinge to fold away. Leaving the field empty means there is
    /// nothing to fold and the island simply stays gone — the screen still
    /// blurs as the lid comes down, which is the part that carries the meaning.
    /// Same rule as `welcome`: an empty field is an instruction to say nothing,
    /// not a request to have something chosen.
    static func farewell(hour: Int, batteryPercent: Int?, custom: String? = nil) -> IslandEvent? {
        guard let title = customTitle(custom) else { return nil }
        return IslandEvent(kind: .lidClosing, title: title,
                           detail: batteryPercent.map { "%\($0)" },
                           progress: nil, symbol: "laptopcomputer.and.arrow.down")
    }

    /// A line one of the user's own rules asked for.
    ///
    /// Same machinery as every other island line, and the same limit on length,
    /// because a rule is not allowed to make a wider island than the app does.
    static func notice(_ text: String) -> IslandEvent {
        IslandEvent(kind: .rule, title: customTitle(text) ?? "Kural", detail: nil,
                    progress: nil, symbol: "wand.and.rays")
    }

    /// The most a hand-written line may be, in characters.
    ///
    /// The island is one line wide. Past this it would either be cut off or
    /// squeeze the panel into something that no longer looks deliberate.
    public static let customTitleLimit = 32

    /// What the user typed, or nothing if they left the field alone.
    ///
    /// Whitespace only counts as leaving it alone, so a stray space cannot
    /// replace the greeting with a blank island.
    public static func customTitle(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(customTitleLimit))
    }

    private static func symbolForGreeting(_ hour: Int) -> String {
        switch hour {
        case 5..<11: return "sunrise.fill"
        case 11..<18: return "sun.max.fill"
        case 18..<23: return "sunset.fill"
        default: return "moon.stars.fill"
        }
    }
}

public extension IslandGeometry {
    /// Width of the event strip, mirroring what the view actually lays out.
    ///
    /// The level bar and the percentage have fixed widths, so any shortfall is
    /// taken out of the title. Underestimating here does not clip the strip, it
    /// silently erases the word that says what changed.
    static func eventWidth(title: String, detail: String?, hasProgress: Bool) -> CGFloat {
        let horizontalPadding: CGFloat = 36   // 18 on each side
        let icon: CGFloat = 22
        let iconGap: CGFloat = 10
        let title = CGFloat(title.count) * 7.2
        var content = horizontalPadding + icon + iconGap + title
        if hasProgress {
            content += 8 + eventLevelWidth
            if detail != nil { content += 6 + eventLevelDetailWidth }
        } else if let detail {
            // The detail sits under the title, so it competes for the same width.
            content = max(content, horizontalPadding + icon + iconGap + CGFloat(detail.count) * 6.4)
        }
        return min(peekMaximumWidth, max(240, content))
    }

    static let eventLevelWidth: CGFloat = 88
    static let eventLevelDetailWidth: CGFloat = 32
}
