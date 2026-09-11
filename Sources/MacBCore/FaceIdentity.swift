import Foundation

/// The nine head angles the guided enrollment walks through.
///
/// Yaw and pitch are in radians and describe where the head should be pointing,
/// so the capture step can tell the user which way to turn without guessing.
public enum FacePose: String, Codable, CaseIterable, Sendable {
    case center
    case left, right, up, down
    case upLeft, upRight, downLeft, downRight

    public var title: String {
        switch self {
        case .center: return "Karşıya bak"
        case .left: return "Sola dön"
        case .right: return "Sağa dön"
        case .up: return "Yukarı bak"
        case .down: return "Aşağı bak"
        case .upLeft: return "Sol üste bak"
        case .upRight: return "Sağ üste bak"
        case .downLeft: return "Sol alta bak"
        case .downRight: return "Sağ alta bak"
        }
    }

    /// Target yaw in radians. Negative is the user's left as the camera sees it.
    public var yaw: Float {
        switch self {
        case .center, .up, .down: return 0
        case .left, .upLeft, .downLeft: return -0.42
        case .right, .upRight, .downRight: return 0.42
        }
    }

    public var pitch: Float {
        switch self {
        case .center, .left, .right: return 0
        case .up, .upLeft, .upRight: return 0.30
        case .down, .downLeft, .downRight: return -0.30
        }
    }

    /// How far off target a frame may be and still count for this pose.
    public static let tolerance: Float = 0.22

    public func accepts(yaw: Float, pitch: Float) -> Bool {
        abs(yaw - self.yaw) <= Self.tolerance && abs(pitch - self.pitch) <= Self.tolerance
    }
}

/// One captured face, reduced to numbers. The frame it came from is discarded.
public struct FaceSample: Codable, Equatable, Sendable {
    public let embedding: [Float]
    public let pose: FacePose?
    public let capturedAt: Date
    /// Vision's capture-quality score in 0...1, when it produced one.
    public let quality: Float?

    public init(embedding: [Float], pose: FacePose?, capturedAt: Date = Date(), quality: Float?) {
        self.embedding = embedding
        self.pose = pose
        self.capturedAt = capturedAt
        self.quality = quality
    }
}

/// An enrolled person, or one variant of a person (with glasses, with a beard).
public struct FaceIdentity: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var isEnabled: Bool
    public var samples: [FaceSample]
    /// Which embedder produced these samples. Samples from another embedder are
    /// never compared, so a model change retires the enrollment instead of
    /// silently degrading matching.
    public var embedderIdentifier: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, isEnabled: Bool = true,
                samples: [FaceSample] = [], embedderIdentifier: String,
                createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.samples = samples
        self.embedderIdentifier = embedderIdentifier
        self.createdAt = createdAt
    }

    /// The averaged template used for the first-pass comparison.
    public var template: [Float]? { FaceEmbedding.average(samples.map(\.embedding)) }

    public var capturedPoses: Set<FacePose> {
        Set(samples.compactMap(\.pose))
    }

    /// Enrollment is complete once every guided pose has at least one sample.
    public var isComplete: Bool { capturedPoses.count == FacePose.allCases.count }

    public var missingPoses: [FacePose] {
        let captured = capturedPoses
        return FacePose.allCases.filter { !captured.contains($0) }
    }
}

/// Which of MacB's own areas a face unlock may open.
///
/// Face unlock never touches the Mac login. It gates MacB's private surfaces
/// only, and each one can be turned off on its own.
public enum ProtectedArea: String, Codable, CaseIterable, Sendable {
    case clipboard, shelf, camera, uninstaller

    public var title: String {
        switch self {
        case .clipboard: return "Pano geçmişi"
        case .shelf: return "Dosya rafı"
        case .camera: return "Kamera önizleme"
        case .uninstaller: return "Uygulama kaldırma"
        }
    }

    public var symbol: String {
        switch self {
        case .clipboard: return "doc.on.clipboard"
        case .shelf: return "tray.full"
        case .camera: return "camera"
        case .uninstaller: return "trash"
        }
    }
}

/// Everything the face-unlock feature persists outside the encrypted vault.
/// None of it is biometric: it is the user's own configuration.
public struct FaceUnlockSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var strictness: FaceMatchStrictness
    public var protectedAreas: Set<ProtectedArea>
    /// Seconds of inactivity after which an unlocked session re-locks.
    public var idleRelockSeconds: TimeInterval
    /// Face matching stays experimental until a distributable model ships.
    public var allowsExperimentalModel: Bool

    public static let idleRelockChoices: [TimeInterval] = [60, 300, 900, 1800]

    public init(isEnabled: Bool = false,
                strictness: FaceMatchStrictness = .strict,
                protectedAreas: Set<ProtectedArea> = [.clipboard, .shelf],
                idleRelockSeconds: TimeInterval = 300,
                allowsExperimentalModel: Bool = false) {
        self.isEnabled = isEnabled
        self.strictness = strictness
        self.protectedAreas = protectedAreas
        self.idleRelockSeconds = idleRelockSeconds
        self.allowsExperimentalModel = allowsExperimentalModel
    }

    public func guards(_ area: ProtectedArea) -> Bool {
        isEnabled && protectedAreas.contains(area)
    }
}
