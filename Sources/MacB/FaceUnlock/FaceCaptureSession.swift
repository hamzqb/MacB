import AVFoundation
import CoreGraphics
import CoreImage
import Foundation

/// A short-lived camera session that exists only while a scan is running.
///
/// It is deliberately separate from the notch's camera preview: frames are
/// handed to one callback, nothing is buffered, nothing is written to disk, and
/// the session is torn down the moment the scan ends. That is what keeps the
/// camera light off when MacB is idle.
final class FaceCaptureSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "dev.hamzababal.MacB.faceCapture")
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private var handler: ((CGImage) -> Void)?
    private var isConfigured = false
    private let stateLock = NSLock()
    private var wantsToRun = false
    /// Frames arrive at 30 Hz; the pipeline only needs a few per second.
    private var lastDelivery = Date.distantPast
    private let minimumInterval: TimeInterval = 0.2

    var isRunning: Bool { session.isRunning }

    static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestAccess() async -> Bool {
        if authorizationStatus == .authorized { return true }
        return await AVCaptureDevice.requestAccess(for: .video)
    }

    /// Starts the camera and delivers frames until `stop()`.
    func start(onFrame: @escaping (CGImage) -> Void) throws {
        handler = onFrame
        try configureIfNeeded()
        stateLock.lock(); wantsToRun = true; stateLock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock(); let shouldStart = self.wantsToRun; self.stateLock.unlock()
            guard shouldStart, !self.session.isRunning else { return }
            self.session.startRunning()
            self.stateLock.lock(); let shouldRemainRunning = self.wantsToRun; self.stateLock.unlock()
            if !shouldRemainRunning { self.session.stopRunning() }
        }
    }

    func stop() {
        handler = nil
        stateLock.lock(); wantsToRun = false; stateLock.unlock()
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video) else {
            throw FaceCaptureError.noCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        session.sessionPreset = .high
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw FaceCaptureError.noCamera
        }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw FaceCaptureError.noCamera
        }
        session.addOutput(output)
        session.commitConfiguration()
        isConfigured = true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let handler else { return }
        let now = Date()
        guard now.timeIntervalSince(lastDelivery) >= minimumInterval else { return }
        lastDelivery = now
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
        handler(cgImage)
    }
}

enum FaceCaptureError: LocalizedError {
    case noCamera
    case denied

    var errorDescription: String? {
        switch self {
        case .noCamera: return "Kamera bulunamadı."
        case .denied: return "Kamera izni verilmedi."
        }
    }
}
