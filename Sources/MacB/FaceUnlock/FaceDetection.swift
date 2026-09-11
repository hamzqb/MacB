import CoreGraphics
import Foundation
import Vision

/// One face Vision found in a single frame.
///
/// `@unchecked` because Vision's landmark object is not marked `Sendable`, even
/// though it is read-only once the request finishes and is never mutated here.
struct DetectedFace: @unchecked Sendable {
    /// Vision's normalised box, origin bottom-left.
    let normalizedBoundingBox: CGRect
    /// The same box in pixels, origin top-left, ready for cropping.
    let boundingBox: CGRect
    let quality: Float?
    let yaw: Float?
    let pitch: Float?
    let roll: Float?
    let landmarks: VNFaceLandmarks2D?
    let imageSize: CGSize

    var area: CGFloat { normalizedBoundingBox.width * normalizedBoundingBox.height }
}

enum FaceDetectionError: LocalizedError {
    case noFace

    var errorDescription: String? {
        switch self {
        case .noFace: return "Karede yüz bulunamadı."
        }
    }
}

/// Pure CPU work over one frame. Nothing is retained and nothing is written out.
enum FaceDetection {
    static func faces(in image: CGImage) throws -> [DetectedFace] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        let qualityRequest = VNDetectFaceCaptureQualityRequest()
        try handler.perform([landmarksRequest, qualityRequest])

        let size = CGSize(width: image.width, height: image.height)
        let qualityByBox = (qualityRequest.results ?? []).reduce(into: [String: Float]()) { result, observation in
            result[key(for: observation.boundingBox)] = observation.faceCaptureQuality
        }

        return (landmarksRequest.results ?? []).map { observation in
            DetectedFace(
                normalizedBoundingBox: observation.boundingBox,
                boundingBox: pixelRect(observation.boundingBox, in: size),
                quality: qualityByBox[key(for: observation.boundingBox)],
                yaw: observation.yaw?.floatValue,
                pitch: observation.pitch?.floatValue,
                roll: observation.roll?.floatValue,
                landmarks: observation.landmarks,
                imageSize: size)
        }
    }

    /// The face a scan should act on: the largest one, so a passer-by in the
    /// background cannot outvote the person sitting at the Mac.
    static func primaryFace(in image: CGImage) throws -> DetectedFace {
        guard let face = try faces(in: image).max(by: { $0.area < $1.area }) else {
            throw FaceDetectionError.noFace
        }
        return face
    }

    /// Crops the face with a little context around it, which the loose-crop
    /// embedder needs and the aligner tolerates.
    static func crop(_ face: DetectedFace, from image: CGImage, padding: CGFloat = 0.2) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let padX = face.boundingBox.width * padding
        let padY = face.boundingBox.height * padding
        let rect = face.boundingBox.insetBy(dx: -padX, dy: -padY).intersection(bounds).integral
        guard rect.width > 1, rect.height > 1 else { return nil }
        return image.cropping(to: rect)
    }

    private static func pixelRect(_ normalized: CGRect, in size: CGSize) -> CGRect {
        let width = normalized.width * size.width
        let height = normalized.height * size.height
        let x = normalized.origin.x * size.width
        let y = (1 - normalized.origin.y) * size.height - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func key(for box: CGRect) -> String {
        String(format: "%.4f-%.4f-%.4f-%.4f", box.origin.x, box.origin.y, box.width, box.height)
    }
}
