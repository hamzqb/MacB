import AppKit
import Combine
import CoreGraphics
import Foundation
import MacBCore

/// What the notch is showing about the scan right now.
enum FaceScanPhase: Equatable {
    case idle
    case scanning
    case success(String)
    case failure(String)
}

/// Face unlock for MacB's own private areas.
///
/// Three rules shape this file, and each one is enforced here rather than in the UI:
///
/// - MacB never learns the Mac password. Falling back means asking
///   LocalAuthentication to run the system's own prompt.
/// - The camera runs only inside `scan()`. There is no idle capture, and the
///   session is torn down in every exit path including the failure ones.
/// - Frames never leave this process and never reach the disk. Only the
///   embedding survives a frame, and only inside the encrypted vault.
@MainActor final class FaceUnlockService: ObservableObject {
    @Published private(set) var settings: FaceUnlockSettings
    @Published private(set) var identities: [FaceIdentity] = []
    @Published private(set) var phase: FaceScanPhase = .idle
    @Published private(set) var scanInstruction = "Karşıya bak"
    @Published private(set) var isVaultUnlocked = false
    /// Mirrors the vault's own flag so the settings page redraws when it changes;
    /// a nested observable object does not republish through its owner.
    @Published private(set) var unlockedAreas: Set<ProtectedArea> = []
    @Published private(set) var isExperimentalModel = false
    @Published private(set) var previewFrame: CGImage?
    @Published private(set) var isFaceVisible = false
    @Published var errorMessage: String?

    /// Enrollment progress, so the UI can draw the nine-pose ring.
    @Published private(set) var enrollmentPose: FacePose?
    @Published private(set) var capturedPoses: Set<FacePose> = []
    @Published private(set) var isEnrolling = false

    let vault = FaceVaultKey()
    private lazy var store = SecureFaceStore(vault: vault)
    private let capture = FaceCaptureSession()
    private let biometrics: BiometricAuthService
    private let defaults: UserDefaults
    private let settingsKey = "faceUnlockSettings"

    private var embedder: FaceEmbedder = VisionFeaturePrintEmbedder()
    private var relockTimer: Timer?
    private var scanDeadline: Task<Void, Never>?
    private var cancelActiveScan: (() -> Void)?
    private var draftSamples: [FaceSample] = []
    private var enrollmentName = ""
    private var poseStartedAt = Date()
    private var lastActivity = Date()

    /// How long a scan may run before it gives up and offers the fallback.
    private let scanTimeout: TimeInterval = 8

    init(biometrics: BiometricAuthService, defaults: UserDefaults = .standard) {
        self.biometrics = biometrics
        self.defaults = defaults
        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(FaceUnlockSettings.self, from: data) {
            settings = decoded
        } else {
            settings = FaceUnlockSettings()
        }
        refreshEmbedder()
    }

    // MARK: - Settings

    var isEnrolled: Bool { store.exists }

    var embedderName: String { embedder.name }

    func update(_ transform: (inout FaceUnlockSettings) -> Void) {
        var copy = settings
        transform(&copy)
        settings = copy
        if let data = try? JSONEncoder().encode(copy) { defaults.set(data, forKey: settingsKey) }
        refreshEmbedder()
    }

    private func refreshEmbedder() {
        let choice = FaceEmbedderFactory.make(allowsExperimentalModel: settings.allowsExperimentalModel)
        embedder = choice.embedder
        isExperimentalModel = choice.isExperimental
    }

    // MARK: - Vault

    /// Opens the vault. The prompt this raises is the system's own Touch ID or
    /// password sheet; MacB never sees what the user types into it.
    func unlockVault(reason: String = "MacB yüz kayıtlarını açmak için kimliğini doğrula") async -> Bool {
        guard let authenticatedContext = await biometrics.authenticateForKeychain(reason: reason) else {
            errorMessage = biometrics.errorMessage ?? "Kimlik doğrulanamadı."
            isVaultUnlocked = false
            return false
        }
        defer { authenticatedContext.invalidate() }
        do {
            // Reuse the authentication the user just passed, so the Keychain
            // read behind `userPresence` does not raise a second sheet.
            try vault.unlock(context: authenticatedContext)
            identities = try store.load()
            isVaultUnlocked = true
            errorMessage = nil
            noteActivity()
            return true
        } catch {
            vault.lock()
            identities = []
            errorMessage = error.localizedDescription
            isVaultUnlocked = false
            return false
        }
    }

    func lockVault() {
        cancelActiveScan?()
        cancelActiveScan = nil
        scanDeadline?.cancel()
        scanDeadline = nil
        capture.stop()
        isEnrolling = false
        enrollmentPose = nil
        draftSamples = []
        capturedPoses = []
        previewFrame = nil
        isFaceVisible = false
        phase = .idle
        vault.lock()
        isVaultUnlocked = false
        identities = []
        unlockedAreas = []
        relockTimer?.invalidate()
        relockTimer = nil
    }

    /// Closes every sensitive resource before sleep, session lock or shutdown.
    func suspend() {
        lockVault()
        errorMessage = nil
    }

    /// Removes every enrolled face and the key that protected them.
    func deleteEnrollment() {
        store.destroy()
        identities = []
        isVaultUnlocked = false
        unlockedAreas = []
        update { $0.isEnabled = false }
    }

    // MARK: - Access

    func isUnlocked(_ area: ProtectedArea) -> Bool {
        guard settings.guards(area) else { return true }
        return unlockedAreas.contains(area)
    }

    /// Opens one area. Tries the face first, then the system prompt.
    ///
    /// A face failure is never the end of the road: the brief asks for Touch ID,
    /// Apple Watch or the Mac password to stay available, and LocalAuthentication
    /// provides all three without MacB handling any of them.
    func requestAccess(to area: ProtectedArea) async -> Bool {
        guard settings.guards(area) else { return true }
        if unlockedAreas.contains(area) { noteActivity(); return true }

        if settings.isEnabled, isEnrolled {
            if !isVaultUnlocked, !(await unlockVault()) { return await fallback(to: area) }
            if await scan() {
                grant(area)
                return true
            }
        }
        return await fallback(to: area)
    }

    private func fallback(to area: ProtectedArea) async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            biometrics.authenticate { continuation.resume(returning: $0) }
        }
        if granted { grant(area) }
        return granted
    }

    private func grant(_ area: ProtectedArea) {
        unlockedAreas.insert(area)
        noteActivity()
        scheduleRelock()
    }

    // MARK: - Idle re-lock

    func noteActivity() { lastActivity = Date() }

    private func scheduleRelock() {
        relockTimer?.invalidate()
        let interval = settings.idleRelockSeconds
        guard interval > 0 else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard Date().timeIntervalSince(self.lastActivity) >= self.settings.idleRelockSeconds else { return }
                self.lockVault()
            }
        }
        relockTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - Scanning

    /// Runs the camera until a frame matches or the deadline passes.
    @discardableResult
    func scan() async -> Bool {
        guard !identities.isEmpty else { return false }
        guard await FaceCaptureSession.requestAccess() else {
            errorMessage = FaceCaptureError.denied.localizedDescription
            return false
        }
        phase = .scanning
        scanInstruction = "Kameraya bak"
        defer { capture.stop() }

        let matched = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            var finished = false
            var consecutiveMatches = 0
            let finish: (Bool) -> Void = { [weak self] success in
                guard !finished else { return }
                finished = true
                self?.capture.stop()
                continuation.resume(returning: success)
            }
            cancelActiveScan = { finish(false) }
            do {
                try capture.start { [weak self] image in
                    guard let self else { return }
                    Task { @MainActor in
                        guard !finished else { return }
                        self.previewFrame = image
                        guard let face = try? FaceDetection.primaryFace(in: image) else {
                            self.isFaceVisible = false
                            return
                        }
                        self.isFaceVisible = true
                        let yaw = face.yaw ?? 0
                        let pitch = face.pitch ?? 0
                        guard abs(yaw) <= 0.42, abs(pitch) <= 0.42,
                              self.matches(image, face: face) else {
                            consecutiveMatches = 0
                            self.scanInstruction = "Kameraya düz bak"
                            return
                        }
                        consecutiveMatches += 1
                        self.scanInstruction = consecutiveMatches < 3 ? "Bir an sabit kal" : "Tanındın"
                        if consecutiveMatches >= 3 {
                            finish(true)
                        }
                    }
                }
            } catch {
                self.errorMessage = error.localizedDescription
                finish(false)
                return
            }
            scanDeadline = Task { [scanTimeout] in
                try? await Task.sleep(nanoseconds: UInt64(scanTimeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                finish(false)
            }
        }
        scanDeadline?.cancel()
        scanDeadline = nil
        cancelActiveScan = nil
        previewFrame = nil
        isFaceVisible = false
        phase = matched ? .success("Tanındı") : .failure("Yüz tanınmadı")
        clearPhaseSoon()
        return matched
    }

    private func matches(_ image: CGImage, face: DetectedFace? = nil) -> Bool {
        guard let embedding = embedding(for: image, detectedFace: face) else { return false }
        return FaceMatcher.bestMatch(embedding,
                                     against: identities,
                                     embedderIdentifier: embedder.identifier,
                                     strictness: settings.strictness) != nil
    }

    /// Detect, align if the model needs it, embed. The frame is released here.
    private func embedding(for image: CGImage, detectedFace: DetectedFace? = nil) -> [Float]? {
        guard let face = detectedFace ?? (try? FaceDetection.primaryFace(in: image)) else { return nil }
        let input: CGImage?
        if embedder.requiresAlignment {
            input = FaceAligner.align(face, in: image)?.image
        } else {
            input = FaceDetection.crop(face, from: image)
        }
        guard let input else { return nil }
        return try? embedder.embedding(for: input)
    }

    private func clearPhaseSoon() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard let self else { return }
            if case .scanning = self.phase { return }
            self.phase = .idle
        }
    }

    // MARK: - Enrollment

    /// Walks the nine poses. Each accepted frame contributes one embedding and
    /// the frame itself is dropped immediately afterwards.
    func beginEnrollment(name: String) async {
        guard await FaceCaptureSession.requestAccess() else {
            errorMessage = FaceCaptureError.denied.localizedDescription
            return
        }
        if !isVaultUnlocked {
            guard await unlockVault(reason: "Yüz kaydı oluşturmak için kimliğini doğrula") else { return }
        }
        enrollmentName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        draftSamples = []
        capturedPoses = []
        enrollmentPose = FacePose.allCases.first
        poseStartedAt = Date()
        isEnrolling = true
        phase = .scanning
        do {
            try capture.start { [weak self] image in
                Task { @MainActor in
                    self?.previewFrame = image
                    self?.consumeEnrollmentFrame(image)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            cancelEnrollment()
        }
    }

    func cancelEnrollment() {
        capture.stop()
        isEnrolling = false
        enrollmentPose = nil
        draftSamples = []
        capturedPoses = []
        previewFrame = nil
        isFaceVisible = false
        phase = .idle
    }

    private func consumeEnrollmentFrame(_ image: CGImage) {
        guard isEnrolling, let pose = enrollmentPose else { return }
        guard let face = try? FaceDetection.primaryFace(in: image) else {
            isFaceVisible = false
            return
        }
        isFaceVisible = true
        guard Date().timeIntervalSince(poseStartedAt) >= 0.45 else { return }
        guard enrollmentPoseMatches(face, pose: pose) else { return }
        if let quality = face.quality, quality < 0.18 { return }

        let input: CGImage?
        if embedder.requiresAlignment {
            input = FaceAligner.align(face, in: image)?.image
        } else {
            input = FaceDetection.crop(face, from: image)
        }
        guard let input, let vector = try? embedder.embedding(for: input) else { return }

        draftSamples.append(FaceSample(embedding: vector, pose: pose, quality: face.quality))
        capturedPoses.insert(pose)
        advancePose()
    }

    private func advancePose() {
        let remaining = FacePose.allCases.filter { !capturedPoses.contains($0) }
        guard let next = remaining.first else {
            finishEnrollment()
            return
        }
        enrollmentPose = next
        poseStartedAt = Date()
    }

    /// Vision may omit pitch or yaw on some cameras and OS revisions. The
    /// available axis still guides the pose; after a short, visible hold the
    /// missing axis no longer leaves enrollment stuck forever.
    private func enrollmentPoseMatches(_ face: DetectedFace, pose: FacePose) -> Bool {
        let heldLongEnoughForMissingAxis = Date().timeIntervalSince(poseStartedAt) >= 1.1
        let yaw = face.yaw.map { abs($0) }
        let pitch = face.pitch.map { abs($0) }

        switch pose {
        case .center:
            return (yaw.map { $0 <= 0.34 } ?? true)
                && (pitch.map { $0 <= 0.34 } ?? true)
        case .left, .right:
            return yaw.map { $0 >= 0.18 } ?? heldLongEnoughForMissingAxis
        case .up, .down:
            return pitch.map { $0 >= 0.12 } ?? heldLongEnoughForMissingAxis
        case .upLeft, .upRight, .downLeft, .downRight:
            let yawMatches = yaw.map { $0 >= 0.16 } ?? heldLongEnoughForMissingAxis
            let pitchMatches = pitch.map { $0 >= 0.10 } ?? heldLongEnoughForMissingAxis
            return yawMatches && pitchMatches
        }
    }

    private func finishEnrollment() {
        capture.stop()
        previewFrame = nil
        isFaceVisible = false
        isEnrolling = false
        enrollmentPose = nil
        let identity = FaceIdentity(name: enrollmentName.isEmpty ? "Ben" : enrollmentName,
                                    samples: draftSamples,
                                    embedderIdentifier: embedder.identifier)
        draftSamples = []
        identities.append(identity)
        do {
            try store.save(identities)
            update { $0.isEnabled = true }
            phase = .success("Yüz kaydedildi")
        } catch {
            identities.removeAll { $0.id == identity.id }
            errorMessage = error.localizedDescription
            phase = .failure("Kayıt saklanamadı")
        }
        clearPhaseSoon()
    }

    // MARK: - Identity management

    func setIdentity(_ id: UUID, enabled: Bool) {
        guard let index = identities.firstIndex(where: { $0.id == id }) else { return }
        identities[index].isEnabled = enabled
        persist()
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = identities.firstIndex(where: { $0.id == id }) else { return }
        identities[index].name = name
        persist()
    }

    func remove(_ id: UUID) {
        identities.removeAll { $0.id == id }
        if identities.isEmpty {
            deleteEnrollment()
        } else {
            persist()
        }
    }

    private func persist() {
        do {
            try store.save(identities)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
