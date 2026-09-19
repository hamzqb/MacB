import Foundation

/// How long "stay awake" lasts and how its countdown reads.
public enum KeepAwakeDuration {
    /// The lengths offered, in minutes. Zero means until turned off.
    public static let choices: [Int] = [30, 60, 120, 240, 0]

    public static func title(minutes: Int) -> String {
        switch minutes {
        case ..<1: return "Kapatana kadar"
        case ..<60: return "\(minutes) dakika"
        case let hours where hours % 60 == 0: return "\(hours / 60) saat"
        default: return "\(minutes / 60) sa \(minutes % 60) dk"
        }
    }

    /// The compact countdown the island shows: "1:05" for an hour and five
    /// minutes, "12 dk" under an hour, "∞" with no end.
    public static func remainingText(until end: Date?, now: Date) -> String {
        guard let end else { return "∞" }
        let seconds = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
        let minutes = (seconds + 59) / 60
        if minutes >= 60 { return String(format: "%d:%02d", minutes / 60, minutes % 60) }
        return "\(minutes) dk"
    }
}
