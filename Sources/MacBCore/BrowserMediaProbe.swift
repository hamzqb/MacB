import Foundation

public struct BrowserMediaProbe: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let isPlaying: Bool
    public let currentTime: Double
    public let duration: Double

    public static func decode(_ json: String) -> BrowserMediaProbe? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["isPlaying"] as? Bool == true else { return nil }
        let rawTitle = (object["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTitle.isEmpty else { return nil }
        return BrowserMediaProbe(
            title: cleanTitle(rawTitle),
            artist: (object["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            isPlaying: true,
            currentTime: finiteNumber(object["currentTime"]),
            duration: finiteNumber(object["duration"])
        )
    }

    private static func finiteNumber(_ value: Any?) -> Double {
        let number = (value as? NSNumber)?.doubleValue ?? 0
        return number.isFinite && number >= 0 ? number : 0
    }

    private static func cleanTitle(_ title: String) -> String {
        let suffixes = [" - YouTube", " — YouTube", " - YouTube Music", " | YouTube Music"]
        for suffix in suffixes where title.hasSuffix(suffix) {
            return String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title
    }
}
