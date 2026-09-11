public enum WindowDesktopLocation: String, Equatable, Sendable {
    case current
    case other
    case unknown
}

public enum WindowDesktopClassifier {
    public static func classify(isOnScreen: Bool?, isMinimized: Bool,
                                isApplicationHidden: Bool) -> WindowDesktopLocation {
        guard !isMinimized, !isApplicationHidden,
              let isOnScreen else { return .unknown }
        return isOnScreen ? .current : .other
    }
}

public struct WindowDesktopAssignment: Equatable, Sendable {
    public let location: WindowDesktopLocation
    public let index: Int?

    public init(location: WindowDesktopLocation, index: Int?) {
        self.location = location
        self.index = index
    }

    public static func resolve(spaceIDs: [UInt64], orderedSpaceIDs: [UInt64], currentSpaceIDs: Set<UInt64>) -> Self {
        guard !spaceIDs.isEmpty else { return .init(location: .unknown, index: nil) }
        let location: WindowDesktopLocation = spaceIDs.contains(where: currentSpaceIDs.contains) ? .current : .other
        let index = orderedSpaceIDs.firstIndex(where: { spaceIDs.contains($0) }).map { $0 + 1 }
        return .init(location: location, index: index)
    }
}
