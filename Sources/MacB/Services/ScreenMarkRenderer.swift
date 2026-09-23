import AppKit
import CoreGraphics

/// Puts numbers on a picture of the screen, over the controls the Mac already
/// knows are there.
///
/// A model looking at a screenshot can see a button perfectly well and still
/// be unable to say where it is: pixel coordinates out of a language model are
/// a guess, and a guess clicks the wrong thing. The Accessibility API knows
/// exactly where every control is, so the two are put together — the frames
/// come from the Mac, the numbers are drawn on the picture, and the model
/// answers with a number. Then "click that" is an index, not an estimate.
///
/// This is the same idea as the marks a screen reader user navigates by, and
/// it costs nothing: the drawing happens on the Mac, and the picture is the
/// one that was going to be sent anyway.
@MainActor enum ScreenMarkRenderer {
    struct Marked {
        let jpeg: Data
        /// One line per number, to send with the picture.
        let legend: [String]
    }

    /// Draws a numbered badge on each control that falls inside the captured
    /// display, and returns the picture with the list of what the numbers mean.
    static func mark(_ image: CGImage, displayFrame: CGRect,
                     controls: [ScreenControlService.Control],
                     maximum: Int = 40, quality: CGFloat = 0.72) -> Marked? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, displayFrame.width > 0 else { return nil }
        let scale = CGFloat(width) / displayFrame.width

        // Only what is actually on this display, big enough to see and small
        // enough to be a control rather than the window it sits in.
        let drawable = controls.compactMap { control -> (ScreenControlService.Control, CGRect)? in
            guard let frame = control.frame, frame.width >= 8, frame.height >= 8,
                  frame.width <= displayFrame.width * 0.95, frame.height <= displayFrame.height * 0.9,
                  displayFrame.intersects(frame) else { return nil }
            let inImage = CGRect(x: (frame.minX - displayFrame.minX) * scale,
                                 y: (frame.minY - displayFrame.minY) * scale,
                                 width: frame.width * scale, height: frame.height * scale)
            return (control, inImage)
        }.prefix(maximum)
        guard !drawable.isEmpty else { return nil }

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let badgeHeight: CGFloat = max(16, CGFloat(height) / 46)
        let font = NSFont.systemFont(ofSize: badgeHeight * 0.68, weight: .bold)
        for (control, box) in drawable {
            // The capture is drawn bottom-up; the frames are top-down.
            let flipped = CGRect(x: box.minX, y: CGFloat(height) - box.maxY,
                                 width: box.width, height: box.height)
            NSColor.systemBlue.withAlphaComponent(0.9).setStroke()
            let outline = NSBezierPath(roundedRect: flipped.insetBy(dx: -1, dy: -1), xRadius: 4, yRadius: 4)
            outline.lineWidth = 2
            outline.stroke()

            let text = "\(control.number)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let textSize = text.size(withAttributes: attributes)
            let badge = CGRect(x: flipped.minX, y: flipped.maxY - badgeHeight,
                               width: max(badgeHeight, textSize.width + badgeHeight * 0.5), height: badgeHeight)
            NSColor.systemBlue.setFill()
            NSBezierPath(roundedRect: badge, xRadius: badgeHeight * 0.28, yRadius: badgeHeight * 0.28).fill()
            text.draw(at: CGPoint(x: badge.midX - textSize.width / 2, y: badge.midY - textSize.height / 2),
                      withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) else { return nil }
        let legend = drawable.map { control, _ in
            "\(control.number). \(control.label) (\(control.role.replacingOccurrences(of: "AX", with: "").lowercased()))"
        }
        return Marked(jpeg: jpeg, legend: legend)
    }
}
