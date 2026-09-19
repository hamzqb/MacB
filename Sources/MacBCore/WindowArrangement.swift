import CoreGraphics
import Foundation

/// A saved arrangement of windows: which application's window was where.
///
/// Frames are in the Accessibility API's global space (origin at the top left
/// of the main display), which is what they are read in and written back in.
public struct WindowArrangement: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// The display setup it was saved on. Restoring on another one still
    /// works; this only decides which arrangement comes back on its own.
    public var displays: DisplaySignature
    public var windows: [SavedWindow]
    /// Put back without being asked when this display setup appears.
    public var restoresAutomatically: Bool
    public var savedAt: Date

    public init(id: UUID = UUID(), name: String, displays: DisplaySignature, windows: [SavedWindow],
                restoresAutomatically: Bool = false, savedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.displays = displays
        self.windows = windows
        self.restoresAutomatically = restoresAutomatically
        self.savedAt = savedAt
    }
}

public struct SavedWindow: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var appName: String
    public var title: String
    /// Its position among the same application's windows when saved, front
    /// to back. The tie-breaker when titles do not decide.
    public var index: Int
    public var frame: CGRect

    public init(bundleIdentifier: String, appName: String, title: String, index: Int, frame: CGRect) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.title = title
        self.index = index
        self.frame = frame
    }
}

/// The set of attached displays, as their bounds. Two setups with the same
/// screens in the same places are the same setup, whatever their IDs.
public struct DisplaySignature: Codable, Equatable, Hashable, Sendable {
    public var bounds: [CGRect]

    public init(bounds: [CGRect]) {
        self.bounds = bounds.map { $0.integral }.sorted {
            $0.minX == $1.minX ? $0.minY < $1.minY : $0.minX < $1.minX
        }
    }

    public var summary: String {
        bounds.count == 1 ? "Tek ekran" : "\(bounds.count) ekran"
    }
}

/// A window that is open now, as the restorer sees it.
public struct LiveWindow: Equatable, Sendable {
    public var bundleIdentifier: String
    public var title: String
    public var index: Int

    public init(bundleIdentifier: String, title: String, index: Int) {
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.index = index
    }
}

public enum WindowArrangementMatcher {
    /// Pairs saved windows with open ones: `result[i]` is the index into
    /// `live` for `saved[i]`, or nil when it has no counterpart.
    ///
    /// Within one application an exact title wins first, so a browser's
    /// "Mail" window finds its way back even if it is now behind another. What
    /// is left is paired in front-to-back order. No open window is used twice.
    public static func match(saved: [SavedWindow], live: [LiveWindow]) -> [Int?] {
        var result = [Int?](repeating: nil, count: saved.count)
        var used = Set<Int>()
        for (savedIndex, window) in saved.enumerated() where !window.title.isEmpty {
            if let liveIndex = live.indices.first(where: {
                !used.contains($0) && live[$0].bundleIdentifier == window.bundleIdentifier
                    && live[$0].title == window.title
            }) {
                result[savedIndex] = liveIndex
                used.insert(liveIndex)
            }
        }
        let byOrder = saved.indices.filter { result[$0] == nil }.sorted { saved[$0].index < saved[$1].index }
        for savedIndex in byOrder {
            let window = saved[savedIndex]
            let candidates = live.indices.filter {
                !used.contains($0) && live[$0].bundleIdentifier == window.bundleIdentifier
            }.sorted { live[$0].index < live[$1].index }
            if let liveIndex = candidates.first {
                result[savedIndex] = liveIndex
                used.insert(liveIndex)
            }
        }
        return result
    }

    /// The arrangement that should come back by itself for `displays`, if any:
    /// the most recently saved one marked automatic for exactly that setup.
    public static func automatic(for displays: DisplaySignature,
                                 in arrangements: [WindowArrangement]) -> WindowArrangement? {
        arrangements.filter { $0.restoresAutomatically && $0.displays == displays }
            .max { $0.savedAt < $1.savedAt }
    }

    /// What the ring's slice applies: the one saved for this display setup, or
    /// failing that the most recent.
    public static func preferred(for displays: DisplaySignature,
                                 in arrangements: [WindowArrangement]) -> WindowArrangement? {
        arrangements.filter { $0.displays == displays }.max { $0.savedAt < $1.savedAt }
            ?? arrangements.max { $0.savedAt < $1.savedAt }
    }
}
