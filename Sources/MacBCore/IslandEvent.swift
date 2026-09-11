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
        case volume, mute, brightness, nowPlaying, charging, unplugged, batteryLow, welcome
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
    /// A level you are actively dragging should follow your finger, so volume and
    /// brightness hold briefly and re-arm on every change. A track change is read
    /// once, so it stays long enough to read a title and no longer.
    public var duration: TimeInterval {
        switch kind {
        case .volume, .mute, .brightness: return 1.2
        case .nowPlaying: return 2.4
        case .charging, .unplugged: return 2.0
        case .batteryLow: return 3.0
        case .welcome: return 2.8
        }
    }

    /// Whether a newer event of the same kind simply replaces this one rather
    /// than queueing behind it. Dragging the volume slider must not queue
    /// thirty panels.
    public func supersedes(_ other: IslandEvent) -> Bool {
        kind == other.kind
    }

    /// An event only outranks what is already showing when it is at least as
    /// important. Otherwise the quieter one waits, and a charger notice cannot
    /// steal the panel while the volume is being dragged.
    public var priority: Int {
        switch kind {
        case .batteryLow: return 3
        case .welcome: return 3
        case .volume, .mute, .brightness: return 2
        case .charging, .unplugged: return 1
        case .nowPlaying: return 0
        }
    }

    public func outranks(_ other: IslandEvent) -> Bool {
        supersedes(other) || priority >= other.priority
    }
}

public extension IslandEvent {
    static func volume(_ level: Double, isMuted: Bool) -> IslandEvent {
        let clamped = min(1, max(0, level))
        if isMuted || clamped == 0 {
            return IslandEvent(kind: .mute, title: "Sessiz", progress: 0, symbol: "speaker.slash.fill")
        }
        return IslandEvent(kind: .volume, title: "Ses",
                           detail: "\(Int((clamped * 100).rounded()))%",
                           progress: clamped, symbol: symbolForVolume(clamped))
    }

    static func brightness(_ level: Double) -> IslandEvent {
        let clamped = min(1, max(0, level))
        return IslandEvent(kind: .brightness, title: "Parlaklık",
                           detail: "\(Int((clamped * 100).rounded()))%",
                           progress: clamped, symbol: "sun.max.fill")
    }

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

    /// The moment the lid comes back up.
    ///
    /// Shown with the same machinery as a volume nudge, because that is exactly
    /// what it is: a line that appears, is read, and leaves on its own.
    static func welcome(hour: Int, time: String, batteryPercent: Int?) -> IslandEvent {
        let detail = [time, batteryPercent.map { "%\($0)" }].compactMap { $0 }.joined(separator: " · ")
        return IslandEvent(kind: .welcome, title: greeting(forHour: hour), detail: detail,
                           progress: nil, symbol: symbolForGreeting(hour))
    }

    /// What to call the time of day. Turkish splits the evening and the night
    /// where a clock does not, so the boundaries are named rather than computed.
    static func greeting(forHour hour: Int) -> String {
        switch hour {
        case 5..<11: return "Günaydın"
        case 11..<18: return "İyi günler"
        case 18..<23: return "İyi akşamlar"
        default: return "İyi geceler"
        }
    }

    private static func symbolForGreeting(_ hour: Int) -> String {
        switch hour {
        case 5..<11: return "sunrise.fill"
        case 11..<18: return "sun.max.fill"
        case 18..<23: return "sunset.fill"
        default: return "moon.stars.fill"
        }
    }

    private static func symbolForVolume(_ level: Double) -> String {
        switch level {
        case ..<0.01: return "speaker.slash.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
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
