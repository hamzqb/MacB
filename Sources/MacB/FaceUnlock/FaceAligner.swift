import CoreGraphics
import Foundation
import Vision

enum FaceAlignmentTier: String, Sendable {
    case fivePoint = "5 nokta"
    case twoPoint = "2 nokta"
    case paddedCrop = "hizalanmamış"
}

struct AlignedFace: Sendable {
    let image: CGImage
    let tier: FaceAlignmentTier
}

/// Warps a detected face onto the canonical 112x112 template.
///
/// A model trained on aligned crops loses most of its accuracy on a loose crop,
/// so this runs before any embedder that asks for alignment.
enum FaceAligner {
    static let outputSize = 112

    /// The standard 112x112 template: left eye, right eye, nose, left mouth, right mouth.
    private static let template: [CGPoint] = [
        CGPoint(x: 38.2946, y: 51.6963),
        CGPoint(x: 73.5318, y: 51.5014),
        CGPoint(x: 56.0252, y: 71.7366),
        CGPoint(x: 41.5493, y: 92.3655),
        CGPoint(x: 70.7299, y: 92.2041)
    ]

    static func align(_ face: DetectedFace, in image: CGImage) -> AlignedFace? {
        if let points = fivePoints(face), let warped = warp(image, from: points, to: template) {
            return AlignedFace(image: warped, tier: .fivePoint)
        }
        if let points = eyePoints(face), let warped = warpFromEyes(image, eyes: points) {
            return AlignedFace(image: warped, tier: .twoPoint)
        }
        guard let cropped = FaceDetection.crop(face, from: image),
              let scaled = scale(cropped) else { return nil }
        return AlignedFace(image: scaled, tier: .paddedCrop)
    }

    // MARK: - Landmarks

    private static func fivePoints(_ face: DetectedFace) -> [CGPoint]? {
        guard let landmarks = face.landmarks,
              let leftEye = centroid(landmarks.leftEye, face: face),
              let rightEye = centroid(landmarks.rightEye, face: face),
              let nose = centroid(landmarks.nose, face: face),
              let outer = landmarks.outerLips,
              outer.pointCount >= 2 else { return nil }
        let lipPoints = imagePoints(outer, face: face)
        guard let leftMouth = lipPoints.min(by: { $0.x < $1.x }),
              let rightMouth = lipPoints.max(by: { $0.x < $1.x }) else { return nil }
        return [leftEye, rightEye, nose, leftMouth, rightMouth]
    }

    private static func eyePoints(_ face: DetectedFace) -> (CGPoint, CGPoint)? {
        guard let landmarks = face.landmarks,
              let left = centroid(landmarks.leftEye, face: face),
              let right = centroid(landmarks.rightEye, face: face) else { return nil }
        return (left, right)
    }

    private static func centroid(_ region: VNFaceLandmarkRegion2D?, face: DetectedFace) -> CGPoint? {
        guard let region, region.pointCount > 0 else { return nil }
        let points = imagePoints(region, face: face)
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    /// Landmarks are normalised inside the face box, origin bottom-left.
    /// This lifts them into whole-image pixels with the origin at the top-left.
    private static func imagePoints(_ region: VNFaceLandmarkRegion2D, face: DetectedFace) -> [CGPoint] {
        region.normalizedPoints.map { point in
            let x = face.boundingBox.origin.x + point.x * face.boundingBox.width
            let y = face.boundingBox.origin.y + (1 - point.y) * face.boundingBox.height
            return CGPoint(x: x, y: y)
        }
    }

    // MARK: - Warping

    /// Least-squares similarity transform (scale, rotation, translation) from the
    /// detected points onto the template, then a redraw at 112x112.
    private static func warp(_ image: CGImage, from source: [CGPoint], to destination: [CGPoint]) -> CGImage? {
        guard source.count == destination.count, source.count >= 2 else { return nil }
        let count = CGFloat(source.count)
        let sourceMean = mean(source)
        let destinationMean = mean(destination)

        var covariance: CGFloat = 0
        var crossCovariance: CGFloat = 0
        var sourceVariance: CGFloat = 0
        for index in 0..<source.count {
            let sx = source[index].x - sourceMean.x
            let sy = source[index].y - sourceMean.y
            let dx = destination[index].x - destinationMean.x
            let dy = destination[index].y - destinationMean.y
            covariance += sx * dx + sy * dy
            crossCovariance += sx * dy - sy * dx
            sourceVariance += sx * sx + sy * sy
        }
        guard sourceVariance > 0 else { return nil }
        let a = covariance / sourceVariance
        let b = crossCovariance / sourceVariance
        guard a.isFinite, b.isFinite, a != 0 || b != 0 else { return nil }

        let transform = CGAffineTransform(a: a, b: b, c: -b, d: a,
                                          tx: destinationMean.x - (a * sourceMean.x - b * sourceMean.y),
                                          ty: destinationMean.y - (b * sourceMean.x + a * sourceMean.y))
        _ = count
        return render(image, transform: transform)
    }

    /// Eyes only: enough to fix roll and scale, not enough to fix a tilted chin.
    private static func warpFromEyes(_ image: CGImage, eyes: (CGPoint, CGPoint)) -> CGImage? {
        warp(image, from: [eyes.0, eyes.1], to: [template[0], template[1]])
    }

    private static func render(_ image: CGImage, transform: CGAffineTransform) -> CGImage? {
        let size = outputSize
        guard let context = CGContext(data: nil, width: size, height: size,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        // Core Graphics draws bottom-up; the template is written top-down.
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)
        context.concatenate(transform)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private static func scale(_ image: CGImage) -> CGImage? {
        let size = outputSize
        guard let context = CGContext(data: nil, width: size, height: size,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()
    }

    private static func mean(_ points: [CGPoint]) -> CGPoint {
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }
}
