import Foundation
import CoreGraphics

public struct WindowDescriptor: Equatable {
    public let id: UInt32
    public let pid: Int32
    public let title: String
    public let frame: CGRect
    public init(id: UInt32, pid: Int32, title: String, frame: CGRect) {
        self.id = id; self.pid = pid; self.title = title; self.frame = frame
    }
}

public enum WindowMatcher {
    /// Require agreeing geometry and process identity. Titles alone cannot identify a window.
    public static func uniqueMatch(pid: Int32, title: String, frame: CGRect, candidates: [WindowDescriptor]) -> UInt32? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        let matches = candidates.filter {
            $0.pid == pid && (title.isEmpty || $0.title.isEmpty || $0.title == title) &&
            abs($0.frame.minX - frame.minX) <= 2 && abs($0.frame.minY - frame.minY) <= 2 &&
            abs($0.frame.width - frame.width) <= 2 && abs($0.frame.height - frame.height) <= 2
        }
        return matches.count == 1 ? matches.first?.id : nil
    }
}
