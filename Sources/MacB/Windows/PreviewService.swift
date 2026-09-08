import AppKit
import Combine
import ScreenCaptureKit
import CoreImage
import MacBCore

private final class PreviewOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    private let context = CIContext(options: [.cacheIntermediates: false])
    let receive: (CGImage) -> Void
    let failed: () -> Void
    init(receive: @escaping (CGImage) -> Void, failed: @escaping () -> Void) {
        self.receive = receive; self.failed = failed
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid, let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let status = attachments.first?[.status] as? Int, status != SCFrameStatus.complete.rawValue { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        if let rendered = context.createCGImage(image, from: image.extent) { receive(rendered) }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { failed() }
}

@MainActor final class PreviewService: ObservableObject {
    @Published private(set) var images: [String: NSImage] = [:]
    @Published private(set) var staleIDs: Set<String> = []
    @Published private(set) var errorMessage: String?
    private var streams: [String: (SCStream, PreviewOutput)] = [:]
    private let outputQueue = DispatchQueue(label: "com.macb.preview", qos: .utility)
    private var generation = 0
    private var stoppingTask: Task<Void, Never>?
    private var desiredIDs: [String] = []
    private var desiredSignature: [String] = []
    private var streamTokens: [String: UUID] = [:]

    func show(_ windows: [WindowRecord]) async {
        let visible = Array(windows.prefix(4))
        let ids = visible.map(\.id)
        let signature = visible.map { "\($0.id)|\($0.title)|\($0.frame)|\($0.isMinimized)|\($0.captureAmbiguous)" }
        guard CGPreflightScreenCaptureAccess() else {
            stop(); images = [:]; staleIDs = []; errorMessage = "Önizlemeler için Ekran Kaydı izni gerekli."; return
        }
        let eligibleIDs = Set(visible.filter { !$0.isMinimized && !$0.captureAmbiguous }.map(\.id))
        if signature == desiredSignature && eligibleIDs.isSubset(of: Set(streams.keys)) { return }
        generation += 1
        desiredIDs = ids
        desiredSignature = signature
        let currentGeneration = generation
        let previous = stoppingTask
        let transition = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == currentGeneration else { return }
            let eligible = eligibleIDs
            await self.retireStreams(except: eligible)
            guard self.generation == currentGeneration else { return }
            let ambiguous = Set(visible.filter(\.captureAmbiguous).map(\.id))
            self.images = self.images.filter { ids.contains($0.key) && !ambiguous.contains($0.key) }
            self.staleIDs = Set(self.images.keys).subtracting(self.streams.keys)
            let missing = visible.filter { eligible.contains($0.id) && self.streams[$0.id] == nil }
            if !missing.isEmpty { await self.startStreams(missing, generation: currentGeneration) }
        }
        stoppingTask = transition
        await transition.value
    }

    private func startStreams(_ visible: [WindowRecord], generation currentGeneration: Int) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard generation == currentGeneration else { return }
            let descriptors = content.windows.map { WindowDescriptor(id: $0.windowID, pid: $0.owningApplication?.processID ?? -1, title: $0.title ?? "", frame: $0.frame) }
            var started = 0
            for window in visible where !window.isMinimized && !window.captureAmbiguous {
                guard generation == currentGeneration else { return }
                guard let id = WindowMatcher.uniqueMatch(pid: window.pid, title: window.title, frame: window.frame, candidates: descriptors),
                      let candidate = content.windows.first(where: { $0.windowID == id }) else { continue }
                let configuration = SCStreamConfiguration()
                configuration.width = 488
                configuration.height = max(1, min(400, Int(488 * window.frame.height / max(window.frame.width, 1))))
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 8)
                configuration.queueDepth = 3
                configuration.capturesAudio = false
                configuration.showsCursor = false
                let streamToken = UUID()
                streamTokens[window.id] = streamToken
                let output = PreviewOutput(receive: { [weak self] image in
                    Task { @MainActor in
                        guard let self, self.streamTokens[window.id] == streamToken, self.desiredIDs.contains(window.id) else { return }
                        self.images[window.id] = NSImage(cgImage: image, size: .zero)
                        self.staleIDs.remove(window.id)
                    }
                }, failed: { [weak self] in
                    Task { @MainActor in
                        guard let self, self.streamTokens[window.id] == streamToken else { return }
                        self.staleIDs.insert(window.id)
                        if !CGPreflightScreenCaptureAccess() { self.images = [:] }
                        self.errorMessage = "Önizleme durdu. Paneli yeniden açın."
                    }
                })
                let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: candidate), configuration: configuration, delegate: output)
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: outputQueue)
                streams[window.id] = (stream, output)
                try await stream.startCapture()
                started += 1
                guard generation == currentGeneration else { return }
            }
            errorMessage = started == 0 && !visible.isEmpty ? "Canlı görüntü eşleştirilemedi." : nil
        } catch {
            guard generation == currentGeneration else { return }
            await retireStreams(); errorMessage = "Önizleme açılamadı. Ekran Kaydı iznini kontrol edin."
        }
    }

    func stop() {
        generation += 1; desiredIDs = []; desiredSignature = []
        staleIDs.formUnion(images.keys)
        let previous = stoppingTask
        stoppingTask = Task { [weak self] in
            await previous?.value
            await self?.retireStreams()
        }
    }

    private func retireStreams(except retainedIDs: Set<String> = []) async {
        let retiredIDs = Set(streams.keys).subtracting(retainedIDs)
        let old = retiredIDs.compactMap { streams.removeValue(forKey: $0) }
        retiredIDs.forEach { streamTokens.removeValue(forKey: $0) }
        for (stream, _) in old { try? await stream.stopCapture() }
    }
}
