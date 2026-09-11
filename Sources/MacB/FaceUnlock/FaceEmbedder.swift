import CoreGraphics
import CoreML
import CryptoKit
import Foundation
import Vision

/// Turns an image of a face into a vector.
///
/// Every sample records which embedder produced it, because two models' vectors
/// live in different spaces and comparing them would produce a similarity number
/// that means nothing.
protocol FaceEmbedder: Sendable {
    var name: String { get }
    var identifier: String { get }
    var requiresAlignment: Bool { get }
    func embedding(for image: CGImage) throws -> [Float]
}

enum FaceEmbedderError: LocalizedError {
    case noObservation
    case unsupportedElementType
    case modelMissing
    case unexpectedOutput(String)

    var errorDescription: String? {
        switch self {
        case .noObservation: return "Vision bu kare için bir imza üretmedi."
        case .unsupportedElementType: return "İmza beklenmeyen bir veri tipiyle geldi."
        case .modelMissing: return "Model dosyası bulunamadı."
        case .unexpectedOutput(let detail): return "Model beklenmeyen çıktı verdi: \(detail)"
        }
    }
}

/// The embedder MacB ships with.
///
/// Vision's image feature print carries no third-party weights and no licence
/// restriction, so it is the only one enabled by default. It is weaker at
/// telling similar faces apart than a dedicated face model, which is why face
/// unlock guards MacB's own areas and never the Mac login.
struct VisionFeaturePrintEmbedder: FaceEmbedder {
    let name = "Vision imzası"
    let identifier = "vision-feature-print-revision-1"
    let requiresAlignment = false

    func embedding(for image: CGImage) throws -> [Float] {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision1
        request.imageCropAndScaleOption = .scaleFill
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        guard let observation = request.results?.first else { throw FaceEmbedderError.noObservation }
        guard observation.elementType == .float else { throw FaceEmbedderError.unsupportedElementType }
        let count = observation.elementCount
        return observation.data.withUnsafeBytes { buffer in
            Array(UnsafeBufferPointer(start: buffer.bindMemory(to: Float.self).baseAddress, count: count))
        }
    }
}

/// An ArcFace-style Core ML model the user supplied themselves.
///
/// MacB ships no face-recognition weights. The public InsightFace w600k_mbf
/// weights that comparable projects use are licensed for non-commercial research
/// only, so bundling them is not an option. This loads a compiled model from
/// Application Support if the user puts one there, and stays behind the
/// experimental flag either way. See THIRD_PARTY_NOTICES.md.
final class ExternalFaceModelEmbedder: FaceEmbedder, @unchecked Sendable {
    let name = "Harici model"
    let identifier: String
    let requiresAlignment = true

    private let model: MLModel
    private let inputName: String
    private let inputSize = FaceAligner.outputSize

    /// Where MacB looks for a user-supplied model.
    static var modelURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("MacB/Models/FaceEmbedding.mlmodelc", isDirectory: true)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: modelURL.path)
    }

    init() throws {
        guard Self.isInstalled else { throw FaceEmbedderError.modelMissing }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        model = try MLModel(contentsOf: Self.modelURL, configuration: configuration)
        guard let input = model.modelDescription.inputDescriptionsByName.keys.sorted().first else {
            throw FaceEmbedderError.unexpectedOutput("giriş adı yok")
        }
        inputName = input
        // The compiled contents distinguish models whose metadata versions match.
        let version = model.modelDescription.metadata[.versionString] as? String ?? "1"
        let digest = Self.modelDigest(at: Self.modelURL)
        identifier = "external-face-model-\(version)-\(digest)"
    }

    private static func modelDigest(at root: URL) -> String {
        let files = (FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])?
            .allObjects as? [URL] ?? []).sorted { $0.path < $1.path }
        var hasher = SHA256()
        for url in files {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            hasher.update(data: Data(url.path.utf8))
            if let data = try? Data(contentsOf: url, options: .mappedIfSafe) { hasher.update(data: data) }
        }
        return hasher.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    func embedding(for image: CGImage) throws -> [Float] {
        guard image.width == inputSize, image.height == inputSize else {
            throw FaceEmbedderError.unexpectedOutput("giriş \(inputSize)x\(inputSize) olmalı")
        }
        guard let buffer = Self.pixelBuffer(from: image, size: inputSize) else {
            throw FaceEmbedderError.unexpectedOutput("piksel arabelleği oluşturulamadı")
        }
        let input = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(pixelBuffer: buffer)])
        let output = try model.prediction(from: input)
        guard let name = output.featureNames.first,
              let array = output.featureValue(for: name)?.multiArrayValue else {
            throw FaceEmbedderError.unexpectedOutput("çıktı dizisi yok")
        }
        return (0..<array.count).map { Float(truncating: array[$0]) }
    }

    private static func pixelBuffer(from image: CGImage, size: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, size, size, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                      width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                        | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return buffer
    }
}

/// Picks the embedder and reports which one is in use.
enum FaceEmbedderFactory {
    /// The external model is used only when the user installed one and turned on
    /// the experimental flag. Otherwise MacB stays on Vision's own feature print.
    static func make(allowsExperimentalModel: Bool) -> (embedder: FaceEmbedder, isExperimental: Bool) {
        guard allowsExperimentalModel, ExternalFaceModelEmbedder.isInstalled,
              let external = try? ExternalFaceModelEmbedder() else {
            return (VisionFeaturePrintEmbedder(), false)
        }
        return (external, true)
    }
}
