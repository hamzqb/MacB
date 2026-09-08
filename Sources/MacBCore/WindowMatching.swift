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
    /// Match inside one process using geometry as the stable identity. AX and ScreenCaptureKit
    /// can report slightly different titles and rounded frames, especially for browsers.
    public static func uniqueMatch(pid: Int32, title: String, frame: CGRect, candidates: [WindowDescriptor]) -> UInt32? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        let ranked = candidates.filter { $0.pid == pid }.compactMap { candidate -> (UInt32, CGFloat)? in
            let dx = abs(candidate.frame.minX - frame.minX)
            let dy = abs(candidate.frame.minY - frame.minY)
            let dw = abs(candidate.frame.width - frame.width)
            let dh = abs(candidate.frame.height - frame.height)
            guard dx <= 14, dy <= 14, dw <= 18, dh <= 18 else { return nil }
            let normalizedGeometry = dx / 14 + dy / 14 + dw / 18 + dh / 18
            let exactTitle = !title.isEmpty && !candidate.title.isEmpty && candidate.title == title
            let titlePenalty: CGFloat = exactTitle || title.isEmpty || candidate.title.isEmpty ? 0 : 0.18
            return (candidate.id, normalizedGeometry + titlePenalty)
        }.sorted { $0.1 < $1.1 }
        guard let best = ranked.first else { return nil }
        if ranked.count > 1 {
            // Near-identical candidates cannot be resolved safely; show the app icon instead.
            guard ranked[1].1 - best.1 > 0.12 else { return nil }
        }
        return best.0
    }
}
