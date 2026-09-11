import AppKit
import SwiftUI

/// Pulls one usable colour out of album art.
///
/// The average of a cover is almost always mud, so this counts colours in a
/// small grid and picks the most colourful one that is actually common, then
/// pushes it into a range that stays legible on black. A cover with no colour
/// in it at all returns nothing, and the island keeps its own accent.
enum ArtworkPalette {
    /// How many cells the cover is reduced to on each side before counting.
    private static let grid = 16

    static func tint(for image: NSImage) -> Color? {
        guard let samples = samples(of: image), !samples.isEmpty else { return nil }

        // Twelve hue buckets, each carrying how much colour it holds in total.
        var weight = [Double](repeating: 0, count: 12)
        var hueSum = [Double](repeating: 0, count: 12)
        var saturationSum = [Double](repeating: 0, count: 12)
        var brightnessSum = [Double](repeating: 0, count: 12)

        for sample in samples {
            // Near-black and near-white pixels carry no hue worth trusting, and
            // most covers are mostly one or the other.
            guard sample.saturation > 0.22, sample.brightness > 0.15, sample.brightness < 0.97 else { continue }
            let bucket = min(11, Int(sample.hue * 12))
            let score = Double(sample.saturation) * Double(sample.brightness)
            weight[bucket] += score
            hueSum[bucket] += Double(sample.hue) * score
            saturationSum[bucket] += Double(sample.saturation) * score
            brightnessSum[bucket] += Double(sample.brightness) * score
        }

        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0 else { return nil }
        let total = weight[best]
        let hue = hueSum[best] / total
        // Clamped so a washed-out cover still tints and a neon one does not glare.
        let saturation = min(0.85, max(0.45, saturationSum[best] / total))
        let brightness = min(0.95, max(0.62, brightnessSum[best] / total))
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    private struct Sample {
        let hue: CGFloat
        let saturation: CGFloat
        let brightness: CGFloat
    }

    private static func samples(of image: NSImage) -> [Sample]? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = grid
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var result: [Sample] = []
        result.reserveCapacity(side * side)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = CGFloat(pixels[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            let color = NSColor(srgbRed: CGFloat(pixels[index]) / 255,
                                green: CGFloat(pixels[index + 1]) / 255,
                                blue: CGFloat(pixels[index + 2]) / 255,
                                alpha: 1)
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, unused: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &unused)
            result.append(Sample(hue: hue, saturation: saturation, brightness: brightness))
        }
        return result
    }
}
