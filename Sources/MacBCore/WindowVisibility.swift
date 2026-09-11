import Foundation

public struct WindowVisibilityCandidate: Equatable {
    public let title: String
    public let bundleIdentifier: String?
    public let isMain: Bool
    public let isFocused: Bool

    public init(title: String, bundleIdentifier: String? = nil, isMain: Bool, isFocused: Bool) {
        self.title = title
        self.bundleIdentifier = bundleIdentifier
        self.isMain = isMain
        self.isFocused = isFocused
    }
}

public enum WindowVisibilityPolicy {
    public static func shouldKeep(_ candidate: WindowVisibilityCandidate,
                                  among processWindows: [WindowVisibilityCandidate]) -> Bool {
        guard isGenericTitle(candidate.title) else { return true }
        guard !candidate.isMain, !candidate.isFocused else { return true }

        let hasNamedPrimaryWindow = processWindows.contains { peer in
            !isGenericTitle(peer.title)
        }
        return !hasNamedPrimaryWindow
    }

    public static func isGenericTitle(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return normalized == "window" || normalized == "pencere"
    }

}
