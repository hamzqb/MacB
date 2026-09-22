import AppKit
@preconcurrency import AVFoundation
import Combine
import SwiftUI

@MainActor final class CameraPreviewService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var errorMessage: String?
    var isAuthorized: Bool { authorizationStatus == .authorized }
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "MacB.CameraPreview", qos: .userInitiated)
    private var generation = 0
    private var attempts = 0
    private var wantsRunning = false
    private var observers: [NSObjectProtocol] = []

    init() {
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            })
        }
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.stop()
                    self?.errorMessage = "Kamera kesintiye uğradı. Kamerayı yeniden açabilirsin."
                }
            })
        }
    }

    deinit {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Invoke only after the user explicitly chooses to open the camera.
    ///
    /// A second call while the preview is already up does nothing; a second
    /// call after a start that never produced a frame — another app had the
    /// camera, the Mac woke with the session in a bad state — starts over
    /// from a clean session instead of waiting on the old one forever.
    func start() {
        if wantsRunning {
            guard !isRunning else { return }
            tearDown()
        }
        wantsRunning = true
        attempts = 0
        generation += 1
        let token = generation
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        errorMessage = nil
        switch authorizationStatus {
        case .authorized: beginCapture(token: token)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self, self.generation == token, self.wantsRunning else { return }
                    self.authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    if granted { self.beginCapture(token: token) }
                    else { self.wantsRunning = false; self.errorMessage = "Kamera izni verilmedi. Sistem Ayarları → Gizlilik ve Güvenlik → Kamera bölümünden izin verebilirsin." }
                }
            }
        default:
            wantsRunning = false
            errorMessage = "Kamera erişimi kapalı. Sistem Ayarları → Gizlilik ve Güvenlik → Kamera bölümünden izin ver."
        }
    }

    func requestAuthorization() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch authorizationStatus {
        case .authorized: errorMessage = nil
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    self?.authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    self?.errorMessage = granted ? nil : "Kamera izni verilmedi."
                }
            }
        default:
            errorMessage = "Kamera erişimi kapalı. Sistem Ayarları’ndan izin ver."
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func stop() {
        wantsRunning = false
        tearDown()
    }

    /// Stops the session and forgets its inputs, so the next start builds the
    /// device again rather than reusing one that has gone away.
    private func tearDown() {
        generation += 1
        isRunning = false
        let session = session
        queue.async {
            if session.isRunning { session.stopRunning() }
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            session.commitConfiguration()
        }
    }

    private func beginCapture(token: Int) {
        let session = session
        queue.async { [weak self] in
            do {
                if session.inputs.isEmpty {
                    guard let device = AVCaptureDevice.default(for: .video) else {
                        throw NSError(domain: "MacB.Camera", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "Kullanılabilir kamera bulunamadı."])
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    session.beginConfiguration()
                    session.sessionPreset = .medium
                    guard session.canAddInput(input) else {
                        session.commitConfiguration()
                        throw NSError(domain: "MacB.Camera", code: 2,
                                      userInfo: [NSLocalizedDescriptionKey: "Kamera şu anda kullanılamıyor."])
                    }
                    session.addInput(input)
                    session.commitConfiguration()
                }
                session.startRunning()
                let running = session.isRunning
                Task { @MainActor in
                    guard let self, self.generation == token, self.wantsRunning else { return }
                    self.isRunning = running
                    guard !running else { self.attempts = 0; return }
                    // One silent retry: the camera is often busy for a moment
                    // after another app lets go of it.
                    if self.attempts < 1 {
                        self.attempts += 1
                        self.wantsRunning = false
                        self.stop()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.start() }
                    } else {
                        self.wantsRunning = false
                        self.errorMessage = "Kamera başlatılamadı. Başka bir uygulama kullanıyor olabilir."
                    }
                }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.wantsRunning = false
                    self.errorMessage = message
                }
            }
        }
    }
}

final class CameraPreviewNSView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
        setAccessibilityElement(true)
        setAccessibilityLabel("Canlı kamera önizlemesi")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func connect(to session: AVCaptureSession?) {
        guard previewLayer.session !== session else { return }
        previewLayer.session = session
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }
}

struct CameraPreviewView: NSViewRepresentable {
    @ObservedObject var service: CameraPreviewService
    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.connect(to: service.session)
        return view
    }
    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) { nsView.connect(to: service.session) }
    static func dismantleNSView(_ nsView: CameraPreviewNSView, coordinator: ()) { nsView.connect(to: nil) }
}
